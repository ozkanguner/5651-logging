# 5651 Loglama Sistemi - Ubuntu Sunucu Tasarımı

## Sistem Genel Bakış

Bu sistem, Türkiye'deki 5651 sayılı kanun gereği internet erişim sağlayıcılarının tutması gereken log kayıtlarını toplamak, işlemek ve saklamak için tasarlanmıştır.

## Mevcut Log Formatı Analizi

```
Jul 22 01:37:54 aksaray-hotspot.trasst.com srcnat: in:ZURICH_HOTEL out:sDT_MODEM, connection-state:new src-mac 0e:26:ad:7f:01:9b, proto TCP (SYN), 172.67.0.212:60792->16.16.163.191:443, len 64
```

### Log Alanları:
- **Tarih/Saat**: Jul 22 01:37:54
- **Hotspot Adı**: aksaray-hotspot.trasst.com
- **İşlem Türü**: srcnat
- **Giriş Interface**: ZURICH_HOTEL
- **Çıkış Interface**: sDT_MODEM
- **Bağlantı Durumu**: new
- **MAC Adresi**: 0e:26:ad:7f:01:9b
- **Protokol**: TCP (SYN)
- **Kaynak IP:Port**: 172.67.0.212:60792
- **Hedef IP:Port**: 16.16.163.191:443
- **Paket Boyutu**: 64

## Ubuntu Sunucu Mimarisi

### 1. Sistem Bileşenleri

#### Log Toplama Katmanı
- **rsyslog**: Merkezi log toplama
- **logrotate**: Log dosyalarının rotasyonu
- **filebeat**: Log dosyalarının izlenmesi

#### Veri İşleme Katmanı
- **Python Scripts**: Log parsing ve normalizasyon
- **Apache Kafka**: Gerçek zamanlı veri akışı
- **Apache Spark**: Büyük veri işleme

#### Veri Saklama Katmanı
- **PostgreSQL**: İlişkisel veri saklama
- **Elasticsearch**: Arama ve analiz
- **Redis**: Önbellek ve geçici veri

#### Web Arayüzü
- **Django/Flask**: Web uygulaması
- **React/Vue.js**: Frontend
- **Nginx**: Web sunucu

### 2. Klasör Yapısı

```
/opt/5651-loglama/
├── config/
│   ├── rsyslog.conf
│   ├── logrotate.conf
│   ├── kafka/
│   └── elasticsearch/
├── scripts/
│   ├── log_parser.py
│   ├── data_processor.py
│   └── backup.sh
├── logs/
│   ├── raw/
│   ├── processed/
│   └── archived/
├── web/
│   ├── static/
│   ├── templates/
│   └── app.py
├── database/
│   ├── migrations/
│   └── schemas/
└── docker/
    ├── docker-compose.yml
    └── Dockerfile
```

### 3. Veritabanı Şeması

#### Ana Tablolar

**hotspots**
- id (PK)
- name
- location
- ip_range
- created_at
- status

**connections**
- id (PK)
- hotspot_id (FK)
- timestamp
- src_mac
- src_ip
- src_port
- dst_ip
- dst_port
- protocol
- packet_size
- connection_state
- in_interface
- out_interface

**users**
- id (PK)
- mac_address
- hotspot_id (FK)
- first_seen
- last_seen
- total_connections

### 4. Log İşleme Akışı

1. **Log Toplama**: rsyslog ile merkezi toplama
2. **Parsing**: Python script ile log ayrıştırma
3. **Normalizasyon**: Veri temizleme ve formatlama
4. **Enrichment**: Ek bilgiler ekleme (coğrafi konum, ISP vb.)
5. **Saklama**: PostgreSQL ve Elasticsearch'e kaydetme
6. **Analiz**: Raporlama ve analiz

### 5. Güvenlik Önlemleri

- **Şifreleme**: TLS/SSL ile veri aktarımı
- **Erişim Kontrolü**: Role-based access control
- **Audit Logging**: Sistem erişim logları
- **Backup**: Otomatik yedekleme
- **Monitoring**: Sistem izleme

### 6. Performans Optimizasyonu

- **Partitioning**: Tarih bazlı tablo bölümleme
- **Indexing**: Veritabanı indeksleme
- **Caching**: Redis önbellek
- **Load Balancing**: Yük dengeleme

### 7. Raporlama

- **Günlük Raporlar**: Bağlantı istatistikleri
- **Aylık Raporlar**: Kullanım analizi
- **Yasal Raporlar**: 5651 kanun gereği raporlar
- **Dashboard**: Gerçek zamanlı izleme

## Kurulum Adımları

### 1. Sistem Gereksinimleri
- Ubuntu 20.04 LTS veya üzeri
- Minimum 8GB RAM
- 500GB disk alanı
- Docker ve Docker Compose

### 2. Kurulum Scripti
```bash
#!/bin/bash
# 5651 Loglama Sistemi Kurulum Scripti

# Sistem güncellemesi
sudo apt update && sudo apt upgrade -y

# Gerekli paketlerin kurulumu
sudo apt install -y python3 python3-pip postgresql redis-server nginx

# Docker kurulumu
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Proje klasörünün oluşturulması
sudo mkdir -p /opt/5651-loglama
sudo chown $USER:$USER /opt/5651-loglama

# Python bağımlılıkları
pip3 install -r requirements.txt

# Veritabanı kurulumu
sudo -u postgres createdb loglama_db
sudo -u postgres createuser loglama_user

# Servis dosyalarının kopyalanması
sudo cp systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable loglama-parser
sudo systemctl enable loglama-web
```

### 3. Konfigürasyon

#### rsyslog.conf
```
# 5651 Loglama için rsyslog konfigürasyonu
module(load="imfile")
module(load="omelasticsearch")

# Log dosyalarını izle
input(type="imfile"
      File="/var/log/hotspot/*.log"
      Tag="5651-loglama"
      Severity="info")

# Elasticsearch'e gönder
action(type="omelasticsearch"
       server="localhost"
       port="9200"
       template="5651-loglama")
```

## Monitoring ve Bakım

### 1. Sistem İzleme
- **Prometheus**: Metrik toplama
- **Grafana**: Dashboard
- **AlertManager**: Uyarı sistemi

### 2. Backup Stratejisi
- **Günlük Backup**: Veritabanı yedekleme
- **Haftalık Backup**: Tam sistem yedekleme
- **Aylık Backup**: Arşiv yedekleme

### 3. Log Retention
- **Ham Loglar**: 1 yıl
- **İşlenmiş Veriler**: 2 yıl
- **Özet Raporlar**: 5 yıl

## Yasal Uyumluluk

### 5651 Kanun Gereksinimleri
- **Kullanıcı Kimlik Bilgileri**: MAC adresi, IP adresi
- **Bağlantı Zamanı**: Tarih/saat bilgisi
- **Hedef Adres**: Erişilen web siteleri
- **Saklama Süresi**: Minimum 2 yıl
- **Güvenlik**: Şifreleme ve erişim kontrolü

### Raporlama Gereksinimleri
- **Günlük İstatistikler**: Bağlantı sayıları
- **Kullanıcı Analizi**: MAC adresi bazlı kullanım
- **Trafik Analizi**: Protokol ve port analizi
- **Coğrafi Analiz**: Konum bazlı istatistikler

## Gelecek Geliştirmeler

1. **Machine Learning**: Anormal trafik tespiti
2. **Real-time Analytics**: Gerçek zamanlı analiz
3. **Mobile App**: Mobil uygulama
4. **API Integration**: Üçüncü parti entegrasyonlar
5. **Cloud Migration**: Bulut tabanlı çözüm 