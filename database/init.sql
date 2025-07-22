-- 5651 Loglama Sistemi Veritabanı Şeması
-- PostgreSQL 15 için optimize edilmiş

-- Veritabanı oluşturma (eğer yoksa)
-- CREATE DATABASE loglama_db;

-- Kullanıcı oluşturma (eğer yoksa)
-- CREATE USER loglama_user WITH PASSWORD 'loglama123';

-- Veritabanına bağlan
\c loglama_db;

-- Uzantıları etkinleştir
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- Hotspot tablosu
CREATE TABLE IF NOT EXISTS hotspots (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    location VARCHAR(255),
    ip_range CIDR,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'active',
    description TEXT,
    contact_info JSONB
);

-- Kullanıcılar tablosu (MAC adresi bazlı)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    mac_address VARCHAR(17) NOT NULL,
    hotspot_id INTEGER REFERENCES hotspots(id) ON DELETE CASCADE,
    first_seen TIMESTAMP WITH TIME ZONE NOT NULL,
    last_seen TIMESTAMP WITH TIME ZONE NOT NULL,
    total_connections INTEGER DEFAULT 1,
    total_bytes BIGINT DEFAULT 0,
    device_info JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(mac_address, hotspot_id)
);

-- Bağlantılar tablosu (ana log tablosu)
CREATE TABLE IF NOT EXISTS connections (
    id BIGSERIAL PRIMARY KEY,
    hotspot_id INTEGER REFERENCES hotspots(id) ON DELETE CASCADE,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    src_mac VARCHAR(17) NOT NULL,
    src_ip INET NOT NULL,
    src_port INTEGER,
    dst_ip INET NOT NULL,
    dst_port INTEGER,
    protocol VARCHAR(10),
    packet_size INTEGER,
    connection_state VARCHAR(50),
    in_interface VARCHAR(100),
    out_interface VARCHAR(100),
    raw_line TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Günlük özet tablosu
CREATE TABLE IF NOT EXISTS daily_summaries (
    id SERIAL PRIMARY KEY,
    hotspot_id INTEGER REFERENCES hotspots(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    total_connections BIGINT DEFAULT 0,
    unique_users INTEGER DEFAULT 0,
    total_bytes BIGINT DEFAULT 0,
    top_protocols JSONB,
    top_destinations JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(hotspot_id, date)
);

-- Aylık özet tablosu
CREATE TABLE IF NOT EXISTS monthly_summaries (
    id SERIAL PRIMARY KEY,
    hotspot_id INTEGER REFERENCES hotspots(id) ON DELETE CASCADE,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    total_connections BIGINT DEFAULT 0,
    unique_users INTEGER DEFAULT 0,
    total_bytes BIGINT DEFAULT 0,
    avg_daily_connections INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(hotspot_id, year, month)
);

-- Sistem logları tablosu
CREATE TABLE IF NOT EXISTS system_logs (
    id SERIAL PRIMARY KEY,
    level VARCHAR(10) NOT NULL,
    message TEXT NOT NULL,
    source VARCHAR(100),
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- İndeksler oluştur
-- Performans için kritik indeksler
CREATE INDEX IF NOT EXISTS idx_connections_timestamp ON connections(timestamp);
CREATE INDEX IF NOT EXISTS idx_connections_hotspot_timestamp ON connections(hotspot_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_connections_src_mac ON connections(src_mac);
CREATE INDEX IF NOT EXISTS idx_connections_dst_ip ON connections(dst_ip);
CREATE INDEX IF NOT EXISTS idx_connections_protocol ON connections(protocol);

-- Kullanıcılar için indeksler
CREATE INDEX IF NOT EXISTS idx_users_mac_address ON users(mac_address);
CREATE INDEX IF NOT EXISTS idx_users_hotspot_last_seen ON users(hotspot_id, last_seen);

-- Özet tabloları için indeksler
CREATE INDEX IF NOT EXISTS idx_daily_summaries_date ON daily_summaries(date);
CREATE INDEX IF NOT EXISTS idx_daily_summaries_hotspot_date ON daily_summaries(hotspot_id, date);
CREATE INDEX IF NOT EXISTS idx_monthly_summaries_year_month ON monthly_summaries(year, month);

-- Sistem logları için indeks
CREATE INDEX IF NOT EXISTS idx_system_logs_created_at ON system_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_system_logs_level ON system_logs(level);

-- Partitioning için hazırlık (büyük veri için)
-- Tarih bazlı partitioning için fonksiyon
CREATE OR REPLACE FUNCTION create_connections_partition(partition_date DATE)
RETURNS VOID AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    partition_name := 'connections_' || to_char(partition_date, 'YYYY_MM');
    start_date := date_trunc('month', partition_date);
    end_date := start_date + interval '1 month';
    
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %I (
            CHECK (timestamp >= %L AND timestamp < %L)
        ) INHERITS (connections)
    ', partition_name, start_date, end_date);
    
    -- Partition için indeksler
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON %I (timestamp)
    ', partition_name || '_timestamp_idx', partition_name);
    
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON %I (hotspot_id, timestamp)
    ', partition_name || '_hotspot_timestamp_idx', partition_name);
    
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON %I (src_mac)
    ', partition_name || '_src_mac_idx', partition_name);
    
    RAISE NOTICE 'Partition % created for date %', partition_name, partition_date;
END;
$$ LANGUAGE plpgsql;

-- Trigger fonksiyonu - yeni partition otomatik oluşturma
CREATE OR REPLACE FUNCTION connections_partition_trigger()
RETURNS TRIGGER AS $$
DECLARE
    partition_date DATE;
BEGIN
    partition_date := date_trunc('month', NEW.timestamp)::DATE;
    PERFORM create_connections_partition(partition_date);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger oluştur
CREATE TRIGGER connections_partition_trigger
    BEFORE INSERT ON connections
    FOR EACH ROW
    EXECUTE FUNCTION connections_partition_trigger();

-- Güncelleme zamanı için trigger fonksiyonu
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Updated_at trigger'ları
CREATE TRIGGER update_hotspots_updated_at
    BEFORE UPDATE ON hotspots
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Örnek veri ekleme fonksiyonu
CREATE OR REPLACE FUNCTION insert_sample_hotspots()
RETURNS VOID AS $$
BEGIN
    INSERT INTO hotspots (name, location, ip_range, description) VALUES
    ('aksaray-hotspot.trasst.com', 'Aksaray, İstanbul', '172.67.0.0/16', 'Aksaray bölgesi hotspot'),
    ('sultanahmet-hotspot.trasst.com', 'Sultanahmet, İstanbul', '172.68.0.0/16', 'Sultanahmet bölgesi hotspot'),
    ('trasst.maslak-hotspot', 'Maslak, İstanbul', '172.69.0.0/16', 'Maslak bölgesi hotspot'),
    ('SISLI_HOTSPOT', 'Şişli, İstanbul', '172.70.0.0/16', 'Şişli bölgesi hotspot'),
    ('log1', 'Test Lokasyonu', '172.71.0.0/16', 'Test hotspot')
    ON CONFLICT (name) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- Örnek hotspot'ları ekle
SELECT insert_sample_hotspots();

-- İstatistik görünümleri
CREATE OR REPLACE VIEW hotspot_statistics AS
SELECT 
    h.id,
    h.name,
    h.location,
    COUNT(DISTINCT u.mac_address) as unique_users,
    COUNT(c.id) as total_connections,
    COALESCE(SUM(c.packet_size), 0) as total_bytes,
    MAX(c.timestamp) as last_activity
FROM hotspots h
LEFT JOIN users u ON h.id = u.hotspot_id
LEFT JOIN connections c ON h.id = c.hotspot_id
WHERE h.status = 'active'
GROUP BY h.id, h.name, h.location;

-- Günlük istatistik görünümü
CREATE OR REPLACE VIEW daily_connection_stats AS
SELECT 
    DATE(timestamp) as connection_date,
    hotspot_id,
    COUNT(*) as connection_count,
    COUNT(DISTINCT src_mac) as unique_users,
    SUM(packet_size) as total_bytes
FROM connections
WHERE timestamp >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(timestamp), hotspot_id
ORDER BY connection_date DESC, hotspot_id;

-- Yetkilendirme
GRANT CONNECT ON DATABASE loglama_db TO loglama_user;
GRANT USAGE ON SCHEMA public TO loglama_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO loglama_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO loglama_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO loglama_user;

-- Gelecekte oluşturulacak tablolar için yetki
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO loglama_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO loglama_user;

-- Sistem loguna başlangıç kaydı
INSERT INTO system_logs (level, message, source, details) VALUES
('INFO', 'Veritabanı şeması başarıyla oluşturuldu', 'init.sql', '{"version": "1.0", "tables_created": 6}'); 