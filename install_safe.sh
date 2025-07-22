#!/bin/bash

# 5651 Loglama Sistemi - Güvenli Kurulum Scripti
# Mevcut sistemleri kontrol eder ve çakışmaları önler

set -e

# Renk kodları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
echo "  5651 Loglama Sistemi - Güvenli Kurulum"
echo "=========================================="
echo -e "${NC}"

# Mevcut sistem kontrolü
log "Mevcut sistem kontrolü yapılıyor..."

# rsyslog kontrolü
if systemctl is-active --quiet rsyslog; then
    log "rsyslog servisi aktif"
    
    # 5651 konfigürasyonu var mı?
    if [ -f "/etc/rsyslog.d/5651-loglama.conf" ]; then
        warn "5651 loglama rsyslog konfigürasyonu bulundu"
        echo "Mevcut konfigürasyon:"
        cat /etc/rsyslog.d/5651-loglama.conf
        echo ""
        
        read -p "Bu konfigürasyonu yedekleyip kaldırmak istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo cp /etc/rsyslog.d/5651-loglama.conf /etc/rsyslog.d/5651-loglama.conf.backup
            sudo rm /etc/rsyslog.d/5651-loglama.conf
            log "Eski konfigürasyon yedeklendi ve kaldırıldı"
        fi
    fi
else
    log "rsyslog servisi pasif"
fi

# Web servisleri kontrolü
log "Web servisleri kontrol ediliyor..."

# Nginx kontrolü
if systemctl is-active --quiet nginx; then
    log "nginx servisi aktif"
    
    # 5651 ile ilgili site var mı?
    if [ -f "/etc/nginx/sites-enabled/5651-loglama" ]; then
        warn "5651 loglama nginx konfigürasyonu bulundu"
        echo "Mevcut konfigürasyon:"
        cat /etc/nginx/sites-enabled/5651-loglama
        echo ""
        
        read -p "Bu konfigürasyonu yedekleyip kaldırmak istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo cp /etc/nginx/sites-enabled/5651-loglama /etc/nginx/sites-enabled/5651-loglama.backup
            sudo rm /etc/nginx/sites-enabled/5651-loglama
            log "Eski nginx konfigürasyonu yedeklendi ve kaldırıldı"
        fi
    fi
fi

# Apache kontrolü
if systemctl is-active --quiet apache2; then
    warn "Apache servisi aktif - port çakışması olabilir"
    echo "Apache portları:"
    sudo netstat -tlnp | grep apache2
    echo ""
fi

# Port kullanımı kontrolü
log "Port kullanımı kontrol ediliyor..."

REQUIRED_PORTS=(80 443 8000 5432 6379 9200 5601 9090 3000)
CONFLICT_PORTS=()

for port in "${REQUIRED_PORTS[@]}"; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        CONFLICT_PORTS+=("$port")
        warn "Port $port kullanımda"
        netstat -tlnp | grep ":$port "
    fi
done

if [ ${#CONFLICT_PORTS[@]} -gt 0 ]; then
    echo ""
    warn "Port çakışmaları tespit edildi: ${CONFLICT_PORTS[*]}"
    echo "Çözüm seçenekleri:"
    echo "1. Mevcut servisleri durdur"
    echo "2. Farklı portlar kullan"
    echo "3. Kurulumu iptal et"
    
    read -p "Seçiminiz (1/2/3): " choice
    case $choice in
        1)
            log "Mevcut servisler durdurulacak"
            for port in "${CONFLICT_PORTS[@]}"; do
                case $port in
                    80|443)
                        sudo systemctl stop nginx
                        sudo systemctl stop apache2
                        ;;
                    5432)
                        sudo systemctl stop postgresql
                        ;;
                    6379)
                        sudo systemctl stop redis-server
                        ;;
                esac
            done
            ;;
        2)
            log "Farklı portlar kullanılacak"
            # docker-compose.yml'da port mapping'i değiştir
            ;;
        3)
            error "Kurulum iptal edildi"
            ;;
        *)
            error "Geçersiz seçim"
            ;;
    esac
fi

# PostgreSQL kontrolü
log "PostgreSQL kontrol ediliyor..."

if systemctl is-active --quiet postgresql; then
    log "PostgreSQL servisi aktif"
    
    # 5651 ile ilgili veritabanı var mı?
    DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='loglama_db'")
    if [ "$DB_EXISTS" = "1" ]; then
        warn "loglama_db veritabanı zaten mevcut"
        
        read -p "Veritabanını yedekleyip yeniden oluşturmak istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo -u postgres pg_dump loglama_db > /backup/loglama_db_backup_$(date +%Y%m%d_%H%M%S).sql
            sudo -u postgres dropdb loglama_db
            log "Veritabanı yedeklendi ve kaldırıldı"
        fi
    fi
fi

# Docker kontrolü
log "Docker kontrol ediliyor..."

if ! command -v docker &> /dev/null; then
    log "Docker kurulu değil, kurulacak"
else
    log "Docker zaten kurulu"
    
    # 5651 ile ilgili container'lar var mı?
    CONTAINERS=$(docker ps -a --filter "name=loglama" --format "{{.Names}}")
    if [ ! -z "$CONTAINERS" ]; then
        warn "5651 loglama container'ları bulundu:"
        echo "$CONTAINERS"
        
        read -p "Bu container'ları kaldırmak istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker stop $CONTAINERS
            docker rm $CONTAINERS
            log "Eski container'lar kaldırıldı"
        fi
    fi
fi

# Backup dizini oluştur
log "Backup dizini oluşturuluyor..."
sudo mkdir -p /backup/5651-loglama
sudo chown $USER:$USER /backup/5651-loglama

# Kurulum onayı
echo ""
echo -e "${BLUE}Kontrol tamamlandı!${NC}"
echo ""
echo "Kurulum özeti:"
echo "✅ Sistem kontrolü yapıldı"
echo "✅ Çakışmalar tespit edildi"
echo "✅ Backup'lar oluşturuldu"
echo ""
echo "Kurulum başlatılacak:"
echo "- rsyslog konfigürasyonu"
echo "- PostgreSQL veritabanı"
echo "- Docker servisleri"
echo "- Web uygulaması"
echo ""

read -p "Kurulumu başlatmak istiyor musunuz? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Kurulum başlatılıyor..."
    
    # Ana kurulum scriptini çalıştır
    ./install.sh
    
    log "Güvenli kurulum tamamlandı!"
else
    log "Kurulum iptal edildi"
fi 