# 5651 Loglama Sistemi

Türkiye'deki 5651 sayılı kanun gereği internet erişim sağlayıcılarının tutması gereken log kayıtlarını toplamak, işlemek ve saklamak için tasarlanmış kapsamlı bir sistem.

## 🎯 Özellikler

### 📊 Veri Toplama ve İşleme
- **Gerçek zamanlı log toplama**: rsyslog ve filebeat ile
- **Otomatik log parsing**: Python tabanlı parser
- **Veri normalizasyonu**: Standart format dönüşümü
- **Büyük veri desteği**: Partitioning ve indeksleme

### 🗄️ Veri Saklama
- **PostgreSQL**: İlişkisel veri saklama
- **Elasticsearch**: Arama ve analiz
- **Redis**: Önbellek ve geçici veri
- **Otomatik backup**: Günlük yedekleme sistemi

### 🌐 Web Arayüzü
- **REST API**: Flask tabanlı API
- **Dashboard**: Gerçek zamanlı izleme
- **Raporlama**: Günlük/aylık raporlar
- **Arama**: Gelişmiş arama özellikleri

### 🔒 Güvenlik
- **Şifreleme**: TLS/SSL desteği
- **Erişim kontrolü**: Role-based access
- **Audit logging**: Sistem erişim logları
- **Fail2ban**: Brute force koruması

### 📈 Monitoring
- **Prometheus**: Metrik toplama
- **Grafana**: Dashboard ve görselleştirme
- **Kibana**: Log analizi
- **Alerting**: Uyarı sistemi

## 🏗️ Sistem Mimarisi

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Hotspot 1     │    │   Hotspot 2     │    │   Hotspot N     │
│   (Log Files)   │    │   (Log Files)   │    │   (Log Files)   │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌─────────────▼─────────────┐
                    │      rsyslog/filebeat     │
                    │     (Log Collection)      │
                    └─────────────┬─────────────┘
                                 │
                    ┌─────────────▼─────────────┐
                    │    Python Log Parser      │
                    │   (Data Processing)       │
                    └─────────────┬─────────────┘
                                 │
          ┌──────────────────────┼──────────────────────┐
          │                      │                      │
┌─────────▼─────────┐  ┌─────────▼─────────┐  ┌─────────▼─────────┐
│    PostgreSQL     │  │   Elasticsearch   │  │      Redis        │
│  (Relational DB)  │  │   (Search/Analyze)│  │     (Cache)       │
└─────────┬─────────┘  └─────────┬─────────┘  └─────────┬─────────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌─────────────▼─────────────┐
                    │    Flask Web App          │
                    │   (API + Dashboard)       │
                    └─────────────┬─────────────┘
                                 │
          ┌──────────────────────┼──────────────────────┐
          │                      │                      │
┌─────────▼─────────┐  ┌─────────▼─────────┐  ┌─────────▼─────────┐
│     Kibana        │  │     Grafana       │  │    Prometheus     │
│  (Log Analytics)  │  │   (Monitoring)    │  │   (Metrics)       │
└───────────────────┘  └───────────────────┘  └───────────────────┘
```

## 📋 Gereksinimler

### Sistem Gereksinimleri
- **İşletim Sistemi**: Ubuntu 20.04 LTS veya üzeri
- **RAM**: Minimum 8GB (önerilen 16GB+)
- **Disk**: Minimum 500GB (SSD önerilen)
- **CPU**: 4 çekirdek (önerilen 8+)
- **Ağ**: Gigabit Ethernet

### Yazılım Gereksinimleri
- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **Python**: 3.8+
- **PostgreSQL**: 15+
- **Redis**: 7+

## 🚀 Kurulum

### 1. Hızlı Kurulum (Otomatik)

```bash
# Repository'yi klonla
git clone https://github.com/your-username/5651-loglama.git
cd 5651-loglama

# Kurulum scriptini çalıştır
chmod +x install.sh
./install.sh
```

### 2. Manuel Kurulum

#### Adım 1: Sistem Hazırlığı
```bash
# Sistem güncellemesi
sudo apt update && sudo apt upgrade -y

# Gerekli paketler
sudo apt install -y python3 python3-pip postgresql redis-server nginx
```

#### Adım 2: Docker Kurulumu
```bash
# Docker kurulumu
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

#### Adım 3: Proje Kurulumu
```bash
# Proje klasörü
sudo mkdir -p /opt/5651-loglama
sudo chown $USER:$USER /opt/5651-loglama
cd /opt/5651-loglama

# Dosyaları kopyala
cp -r /path/to/your/project/* .

# Python bağımlılıkları
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### Adım 4: Veritabanı Kurulumu
```bash
# PostgreSQL konfigürasyonu
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Veritabanı oluştur
sudo -u postgres createdb loglama_db
sudo -u postgres createuser loglama_user
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE loglama_db TO loglama_user;"

# Şema yükle
psql -h localhost -U loglama_user -d loglama_db -f database/init.sql
```

#### Adım 5: Docker Servisleri
```bash
# Docker servislerini başlat
cd docker
docker-compose up -d
```

## 📖 Kullanım

### Web Arayüzü
- **Ana Dashboard**: http://your-server:8000
- **Kibana**: http://your-server:5601
- **Grafana**: http://your-server:3000
- **Prometheus**: http://your-server:9090

### API Kullanımı

#### Hotspot Listesi
```bash
curl http://your-server:8000/api/hotspots
```

#### Bağlantı Kayıtları
```bash
curl "http://your-server:8000/api/connections?limit=100&hotspot_id=1"
```

#### Arama
```bash
curl "http://your-server:8000/api/search?q=192.168.1.1"
```

#### İstatistikler
```bash
curl http://your-server:8000/api/statistics
```

### Log Dosyası İşleme

#### Manuel İşleme
```bash
# Test modu
python scripts/log_parser.py --file /path/to/logfile.log --dry-run

# Gerçek işleme
python scripts/log_parser.py --file /path/to/logfile.log
```

#### Otomatik İşleme
```bash
# Servis durumu
sudo systemctl status loglama-parser

# Servisi başlat
sudo systemctl start loglama-parser

# Servisi etkinleştir
sudo systemctl enable loglama-parser
```

## 🔧 Konfigürasyon

### Ana Konfigürasyon Dosyaları

#### `config/parser.json`
```json
{
  "postgres": {
    "host": "localhost",
    "port": 5432,
    "database": "loglama_db",
    "user": "loglama_user",
    "password": "loglama123"
  },
  "redis": {
    "host": "localhost",
    "port": 6379,
    "db": 0
  },
  "elasticsearch": {
    "host": "localhost",
    "port": 9200
  }
}
```

#### `docker/docker-compose.yml`
Docker servislerinin konfigürasyonu için ana dosya.

### Ortam Değişkenleri
```bash
# .env dosyası oluştur
cat > .env << EOF
POSTGRES_PASSWORD=your_secure_password
GRAFANA_PASSWORD=your_grafana_password
SECRET_KEY=your_secret_key
DEBUG=False
EOF
```

## 📊 Veritabanı Şeması

### Ana Tablolar

#### `hotspots`
Hotspot bilgileri
```sql
CREATE TABLE hotspots (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    location VARCHAR(255),
    ip_range CIDR,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'active'
);
```

#### `connections`
Bağlantı kayıtları (ana log tablosu)
```sql
CREATE TABLE connections (
    id BIGSERIAL PRIMARY KEY,
    hotspot_id INTEGER REFERENCES hotspots(id),
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    src_mac VARCHAR(17) NOT NULL,
    src_ip INET NOT NULL,
    dst_ip INET NOT NULL,
    protocol VARCHAR(10),
    packet_size INTEGER,
    connection_state VARCHAR(50)
);
```

#### `users`
Kullanıcı aktiviteleri (MAC adresi bazlı)
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    mac_address VARCHAR(17) NOT NULL,
    hotspot_id INTEGER REFERENCES hotspots(id),
    first_seen TIMESTAMP WITH TIME ZONE NOT NULL,
    last_seen TIMESTAMP WITH TIME ZONE NOT NULL,
    total_connections INTEGER DEFAULT 1
);
```

## 🔍 Log Formatı

Sistem aşağıdaki log formatını destekler:

```
Jul 22 01:37:54 aksaray-hotspot.trasst.com srcnat: in:ZURICH_HOTEL out:sDT_MODEM, connection-state:new src-mac 0e:26:ad:7f:01:9b, proto TCP (SYN), 172.67.0.212:60792->16.16.163.191:443, len 64
```

### Log Alanları
- **Tarih/Saat**: `Jul 22 01:37:54`
- **Hotspot Adı**: `aksaray-hotspot.trasst.com`
- **İşlem Türü**: `srcnat`
- **Giriş Interface**: `ZURICH_HOTEL`
- **Çıkış Interface**: `sDT_MODEM`
- **Bağlantı Durumu**: `new`
- **MAC Adresi**: `0e:26:ad:7f:01:9b`
- **Protokol**: `TCP (SYN)`
- **Kaynak IP:Port**: `172.67.0.212:60792`
- **Hedef IP:Port**: `16.16.163.191:443`
- **Paket Boyutu**: `64`

## 📈 Raporlama

### Günlük Raporlar
- Bağlantı sayıları
- Benzersiz kullanıcı sayısı
- Toplam trafik miktarı
- Protokol dağılımı

### Aylık Raporlar
- Kullanım trendleri
- Hotspot performansı
- Kullanıcı davranış analizi

### Yasal Raporlar (5651 Kanun)
- Kullanıcı kimlik bilgileri
- Bağlantı zamanları
- Erişilen hedef adresler
- Saklama süresi uyumluluğu

## 🔒 Güvenlik

### Güvenlik Önlemleri
- **Şifreleme**: TLS/SSL ile veri aktarımı
- **Erişim Kontrolü**: Role-based access control
- **Audit Logging**: Sistem erişim logları
- **Backup**: Otomatik yedekleme
- **Monitoring**: Sistem izleme

### Güvenlik Duvarı Kuralları
```bash
# UFW kuralları
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8000/tcp
sudo ufw --force enable
```

## 🛠️ Bakım

### Günlük Bakım
```bash
# Log rotasyonu
sudo logrotate /etc/logrotate.d/5651-loglama

# Backup kontrolü
ls -la /opt/5651-loglama/backups/

# Disk kullanımı kontrolü
df -h /opt/5651-loglama/
```

### Haftalık Bakım
```bash
# Veritabanı optimizasyonu
psql -h localhost -U loglama_user -d loglama_db -c "VACUUM ANALYZE;"

# Eski log dosyalarını temizle
find /opt/5651-loglama/logs/archived -name "*.log" -mtime +365 -delete

# Sistem güncellemesi
sudo apt update && sudo apt upgrade -y
```

### Aylık Bakım
```bash
# Tam sistem backup
/opt/5651-loglama/scripts/backup.sh

# Performans analizi
psql -h localhost -U loglama_user -d loglama_db -c "SELECT * FROM pg_stat_user_tables;"

# Güvenlik taraması
sudo fail2ban-client status
```

## 🐛 Sorun Giderme

### Yaygın Sorunlar

#### 1. Veritabanı Bağlantı Hatası
```bash
# PostgreSQL durumu kontrol et
sudo systemctl status postgresql

# Bağlantı test et
psql -h localhost -U loglama_user -d loglama_db -c "SELECT 1;"
```

#### 2. Log Parser Çalışmıyor
```bash
# Servis durumu
sudo systemctl status loglama-parser

# Log dosyalarını kontrol et
sudo journalctl -u loglama-parser -f

# Manuel test
python scripts/log_parser.py --file test.log --dry-run
```

#### 3. Web Uygulaması Erişim Sorunu
```bash
# Flask uygulaması durumu
sudo systemctl status loglama-web

# Port kontrolü
netstat -tlnp | grep :8000

# Nginx durumu
sudo systemctl status nginx
```

#### 4. Docker Servisleri Sorunu
```bash
# Docker servisleri durumu
cd /opt/5651-loglama/docker
docker-compose ps

# Log kontrolü
docker-compose logs -f

# Servisleri yeniden başlat
docker-compose restart
```

## 📞 Destek

### Dokümantasyon
- [API Dokümantasyonu](docs/api.md)
- [Konfigürasyon Rehberi](docs/configuration.md)
- [Güvenlik Rehberi](docs/security.md)

### İletişim
- **E-posta**: support@your-company.com
- **GitHub Issues**: [Proje Issues](https://github.com/your-username/5651-loglama/issues)

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır. Detaylar için [LICENSE](LICENSE) dosyasına bakın.

## 🤝 Katkıda Bulunma

1. Fork yapın
2. Feature branch oluşturun (`git checkout -b feature/amazing-feature`)
3. Commit yapın (`git commit -m 'Add amazing feature'`)
4. Push yapın (`git push origin feature/amazing-feature`)
5. Pull Request oluşturun

## 📝 Changelog

### v1.0.0 (2024-01-XX)
- İlk sürüm
- Temel log parsing
- Web dashboard
- PostgreSQL entegrasyonu
- Docker desteği

## 🙏 Teşekkürler

- [Flask](https://flask.palletsprojects.com/) - Web framework
- [PostgreSQL](https://www.postgresql.org/) - Veritabanı
- [Elasticsearch](https://www.elastic.co/) - Arama motoru
- [Docker](https://www.docker.com/) - Konteynerizasyon
- [Grafana](https://grafana.com/) - Monitoring 