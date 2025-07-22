#!/bin/bash

# 5651 Loglama Sistemi - Ubuntu Kurulum Scripti
# Bu script Ubuntu sunucuda 5651 loglama sistemini kurar

set -e  # Hata durumunda scripti durdur

# Renk kodları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log fonksiyonu
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Başlık
echo -e "${BLUE}"
echo "=========================================="
echo "  5651 Loglama Sistemi Kurulum Scripti"
echo "=========================================="
echo -e "${NC}"

# Root kontrolü
if [[ $EUID -eq 0 ]]; then
   error "Bu script root kullanıcısı ile çalıştırılmamalıdır!"
fi

# Sistem kontrolü
log "Sistem kontrolü yapılıyor..."

# Ubuntu versiyonu kontrolü
if ! grep -q "Ubuntu" /etc/os-release; then
    error "Bu script sadece Ubuntu sistemlerde çalışır!"
fi

UBUNTU_VERSION=$(grep "VERSION_ID" /etc/os-release | cut -d'"' -f2)
log "Ubuntu versiyonu: $UBUNTU_VERSION"

# Sistem güncellemesi
log "Sistem güncelleniyor..."
sudo apt update && sudo apt upgrade -y

# Gerekli paketlerin kurulumu
log "Gerekli paketler kuruluyor..."
sudo apt install -y \
    curl \
    wget \
    git \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    python3 \
    python3-pip \
    python3-venv \
    postgresql \
    postgresql-contrib \
    redis-server \
    nginx \
    ufw \
    fail2ban \
    htop \
    vim \
    tree

# Docker kurulumu
log "Docker kuruluyor..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    log "Docker kuruldu. Sistemi yeniden başlatmanız gerekebilir."
else
    log "Docker zaten kurulu."
fi

# Docker Compose kurulumu
log "Docker Compose kuruluyor..."
if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    log "Docker Compose kuruldu."
else
    log "Docker Compose zaten kurulu."
fi

# Proje klasörünün oluşturulması
log "Proje klasörü oluşturuluyor..."
sudo mkdir -p /opt/5651-loglama
sudo chown $USER:$USER /opt/5651-loglama
cd /opt/5651-loglama

# Alt klasörlerin oluşturulması
log "Klasör yapısı oluşturuluyor..."
mkdir -p {config,scripts,logs/{raw,processed,archived},web/{static,templates},database,docker}

# Python sanal ortamı oluşturma
log "Python sanal ortamı oluşturuluyor..."
python3 -m venv venv
source venv/bin/activate

# Python bağımlılıkları
log "Python bağımlılıkları kuruluyor..."
pip install --upgrade pip
pip install -r requirements.txt

# PostgreSQL konfigürasyonu
log "PostgreSQL konfigürasyonu yapılıyor..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Veritabanı ve kullanıcı oluşturma
sudo -u postgres psql -c "CREATE DATABASE loglama_db;" || warn "Veritabanı zaten mevcut"
sudo -u postgres psql -c "CREATE USER loglama_user WITH PASSWORD 'loglama123';" || warn "Kullanıcı zaten mevcut"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE loglama_db TO loglama_user;"

# Redis konfigürasyonu
log "Redis konfigürasyonu yapılıyor..."
sudo systemctl start redis-server
sudo systemctl enable redis-server

# Nginx konfigürasyonu
log "Nginx konfigürasyonu yapılıyor..."
sudo systemctl start nginx
sudo systemctl enable nginx

# Güvenlik duvarı konfigürasyonu
log "Güvenlik duvarı konfigürasyonu yapılıyor..."
sudo ufw --force enable
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8000/tcp  # Web uygulaması
sudo ufw allow 5432/tcp  # PostgreSQL
sudo ufw allow 6379/tcp  # Redis
sudo ufw allow 9200/tcp  # Elasticsearch
sudo ufw allow 5601/tcp  # Kibana
sudo ufw allow 9090/tcp  # Prometheus
sudo ufw allow 3000/tcp  # Grafana

# Fail2ban konfigürasyonu
log "Fail2ban konfigürasyonu yapılıyor..."
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

# Konfigürasyon dosyalarının kopyalanması
log "Konfigürasyon dosyaları kopyalanıyor..."

# rsyslog konfigürasyonu
sudo tee /etc/rsyslog.d/5651-loglama.conf > /dev/null <<EOF
# 5651 Loglama Sistemi rsyslog konfigürasyonu
module(load="imfile")
module(load="omelasticsearch")

# Log dosyalarını izle
input(type="imfile"
      File="/opt/5651-loglama/logs/raw/*.log"
      Tag="5651-loglama"
      Severity="info")

# Elasticsearch'e gönder
action(type="omelasticsearch"
       server="localhost"
       port="9200"
       template="5651-loglama")
EOF

# logrotate konfigürasyonu
sudo tee /etc/logrotate.d/5651-loglama > /dev/null <<EOF
/opt/5651-loglama/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $USER $USER
    postrotate
        systemctl reload rsyslog
    endscript
}
EOF

# Systemd servis dosyaları
log "Systemd servis dosyaları oluşturuluyor..."

# Log Parser Service
sudo tee /etc/systemd/system/loglama-parser.service > /dev/null <<EOF
[Unit]
Description=5651 Loglama Parser Service
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/5651-loglama
Environment=PATH=/opt/5651-loglama/venv/bin
ExecStart=/opt/5651-loglama/venv/bin/python scripts/log_parser.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Web Application Service
sudo tee /etc/systemd/system/loglama-web.service > /dev/null <<EOF
[Unit]
Description=5651 Loglama Web Application
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/5651-loglama/web
Environment=PATH=/opt/5651-loglama/venv/bin
Environment=FLASK_APP=app.py
Environment=FLASK_ENV=production
ExecStart=/opt/5651-loglama/venv/bin/python app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Servisleri etkinleştir
sudo systemctl daemon-reload
sudo systemctl enable loglama-parser
sudo systemctl enable loglama-web

# Nginx konfigürasyonu
sudo tee /etc/nginx/sites-available/5651-loglama > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    # Web uygulaması
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # API
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Kibana
    location /kibana/ {
        proxy_pass http://127.0.0.1:5601/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Grafana
    location /grafana/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Prometheus
    location /prometheus/ {
        proxy_pass http://127.0.0.1:9090/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Nginx site'ını etkinleştir
sudo ln -sf /etc/nginx/sites-available/5651-loglama /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

# Backup scripti oluşturma
log "Backup scripti oluşturuluyor..."
tee scripts/backup.sh > /dev/null <<EOF
#!/bin/bash
# 5651 Loglama Sistemi Backup Scripti

BACKUP_DIR="/opt/5651-loglama/backups"
DATE=\$(date +%Y%m%d_%H%M%S)

mkdir -p \$BACKUP_DIR

# PostgreSQL backup
pg_dump -h localhost -U loglama_user -d loglama_db > \$BACKUP_DIR/loglama_db_\$DATE.sql

# Log dosyaları backup
tar -czf \$BACKUP_DIR/logs_\$DATE.tar.gz -C /opt/5651-loglama logs/

# Konfigürasyon dosyaları backup
tar -czf \$BACKUP_DIR/config_\$DATE.tar.gz -C /opt/5651-loglama config/

# Eski backup'ları temizle (30 günden eski)
find \$BACKUP_DIR -name "*.sql" -mtime +30 -delete
find \$BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "Backup tamamlandı: \$DATE"
EOF

chmod +x scripts/backup.sh

# Cron job ekleme
log "Cron job'ları ekleniyor..."
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/5651-loglama/scripts/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * find /opt/5651-loglama/logs/archived -name '*.log' -mtime +365 -delete") | crontab -

# İlk backup'ı çalıştır
log "İlk backup çalıştırılıyor..."
scripts/backup.sh

# Docker Compose ile servisleri başlat
log "Docker servisleri başlatılıyor..."
cd docker
docker-compose up -d

# Servisleri başlat
log "Sistem servisleri başlatılıyor..."
sudo systemctl start loglama-parser
sudo systemctl start loglama-web

# Kurulum tamamlandı
echo -e "${GREEN}"
echo "=========================================="
echo "  5651 Loglama Sistemi Kurulum Tamamlandı!"
echo "=========================================="
echo -e "${NC}"

log "Kurulum başarıyla tamamlandı!"
echo ""
echo "Sistem Bilgileri:"
echo "  - Web Uygulaması: http://$(hostname -I | awk '{print $1}'):8000"
echo "  - Kibana: http://$(hostname -I | awk '{print $1}'):5601"
echo "  - Grafana: http://$(hostname -I | awk '{print $1}'):3000"
echo "  - Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo ""
echo "Veritabanı Bilgileri:"
echo "  - Host: localhost"
echo "  - Port: 5432"
echo "  - Database: loglama_db"
echo "  - User: loglama_user"
echo "  - Password: loglama123"
echo ""
echo "Önemli Notlar:"
echo "  - Sistem yeniden başlatıldıktan sonra Docker kullanıcı grubu aktif olacak"
echo "  - Log dosyaları /opt/5651-loglama/logs/ klasöründe saklanacak"
echo "  - Günlük backup'lar otomatik olarak çalışacak"
echo "  - Güvenlik duvarı kuralları uygulandı"
echo ""
echo "Servis Durumu Kontrolü:"
sudo systemctl status loglama-parser --no-pager -l
sudo systemctl status loglama-web --no-pager -l
echo ""
log "Kurulum tamamlandı!" 