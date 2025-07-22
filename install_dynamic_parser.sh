#!/bin/bash

echo "=== 5651 Dynamic Log Parser Kurulum ==="

# 1. Systemd service oluştur
echo "1. Systemd service oluşturuluyor..."
cat > /etc/systemd/system/5651-dynamic-parser.service << 'EOF'
[Unit]
Description=5651 Dynamic Log Parser Service
After=network.target postgresql.service redis.service
Wants=postgresql.service redis.service

[Service]
Type=simple
User=root
WorkingDirectory=/root/logweb/5651-logging
Environment=PATH=/root/logweb/5651-logging/venv/bin
ExecStart=/root/logweb/5651-logging/venv/bin/python scripts/dynamic_log_parser.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 2. Service'i etkinleştir ve başlat
echo "2. Service etkinleştiriliyor..."
systemctl daemon-reload
systemctl enable 5651-dynamic-parser
systemctl start 5651-dynamic-parser

# 3. Durumu kontrol et
echo "3. Service durumu kontrol ediliyor..."
sleep 3
systemctl status 5651-dynamic-parser --no-pager -l

# 4. Log dizinini oluştur
echo "4. Log dizini oluşturuluyor..."
mkdir -p /root/logweb/5651-logging/logs

# 5. Test script'i oluştur
echo "5. Test script'i oluşturuluyor..."
cat > /root/logweb/5651-logging/test_dynamic_parser.sh << 'EOF'
#!/bin/bash

echo "=== 5651 Dynamic Log Parser Test ==="

# 1. Mevcut hotspot'ları kontrol et
echo "1. Mevcut hotspot'lar kontrol ediliyor..."
echo "Mevcut hotspot klasörleri:"
ls -la /var/log/remote/

# 2. Dynamic parser servisini kontrol et
echo "2. Dynamic parser servisi kontrol ediliyor..."
if systemctl is-active 5651-dynamic-parser > /dev/null; then
    echo "✅ Dynamic parser servisi çalışıyor"
    systemctl status 5651-dynamic-parser --no-pager -l
else
    echo "❌ Dynamic parser servisi çalışmıyor, başlatılıyor..."
    systemctl start 5651-dynamic-parser
    sleep 5
    systemctl status 5651-dynamic-parser --no-pager -l
fi

# 3. Log dosyalarını kontrol et
echo "3. Log dosyaları kontrol ediliyor..."
for dir in /var/log/remote/*/; do
    hotspot=$(basename "$dir")
    echo "Hotspot: $hotspot"
    log_count=$(find "$dir" -name "*.log" | wc -l)
    echo "  Log dosyası sayısı: $log_count"
    if [ $log_count -gt 0 ]; then
        latest_log=$(find "$dir" -name "*.log" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        echo "  En son log: $(basename "$latest_log")"
        echo "  Son satır: $(tail -1 "$latest_log" 2>/dev/null | cut -c1-100)..."
    fi
done

# 4. Veritabanı kontrolü
echo "4. Veritabanı kontrol ediliyor..."
echo "Hotspot sayısı:"
PGPASSWORD=Zkngnr81. psql -h localhost -U loglama_user -d loglama_db -c "SELECT COUNT(*) FROM hotspots;" 2>/dev/null

echo "Bağlantı sayısı:"
PGPASSWORD=Zkngnr81. psql -h localhost -U loglama_user -d loglama_db -c "SELECT COUNT(*) FROM connections;" 2>/dev/null

echo "Son bağlantılar:"
PGPASSWORD=Zkngnr81. psql -h localhost -U loglama_user -d loglama_db -c "SELECT h.name, c.src_ip, c.dst_ip, c.timestamp FROM connections c JOIN hotspots h ON c.hotspot_id = h.id ORDER BY c.timestamp DESC LIMIT 5;" 2>/dev/null

# 5. Web arayüzü testi
echo "5. Web arayüzü test ediliyor..."
if curl -s http://localhost:8000/api/hotspots > /dev/null; then
    echo "✅ Hotspot API çalışıyor"
    echo "Kayıtlı hotspot'lar:"
    curl -s http://localhost:8000/api/hotspots | python -m json.tool
else
    echo "❌ Hotspot API erişilemiyor"
fi

echo "=== Test Tamamlandı ==="
echo "Dynamic parser servisi: 5651-dynamic-parser"
echo "Log dosyası: /root/logweb/5651-logging/logs/dynamic_parser.log"
echo "Servis durumu: systemctl status 5651-dynamic-parser"
EOF

chmod +x /root/logweb/5651-logging/test_dynamic_parser.sh

# 6. Monitoring script'i oluştur
echo "6. Monitoring script'i oluşturuluyor..."
cat > /root/logweb/5651-logging/monitor_parser.sh << 'EOF'
#!/bin/bash

echo "=== 5651 Dynamic Parser Monitoring ==="

# Servis durumu
echo "📊 Servis Durumu:"
systemctl is-active 5651-dynamic-parser

# Son loglar
echo "📝 Son Loglar:"
tail -10 /root/logweb/5651-logging/logs/dynamic_parser.log

# Hotspot sayısı
echo "🏢 Hotspot Sayısı:"
PGPASSWORD=Zkngnr81. psql -h localhost -U loglama_user -d loglama_db -c "SELECT COUNT(*) FROM hotspots;" 2>/dev/null

# Bağlantı sayısı
echo "🔗 Bağlantı Sayısı:"
PGPASSWORD=Zkngnr81. psql -h localhost -U loglama_user -d loglama_db -c "SELECT COUNT(*) FROM connections;" 2>/dev/null

# Son aktiviteler
echo "⏰ Son Aktiviteler:"
PGPASSWORD=Zkngnr81. psql -h localhost -U loglama_user -d loglama_db -c "SELECT h.name, c.timestamp, c.src_ip, c.dst_ip FROM connections c JOIN hotspots h ON c.hotspot_id = h.id ORDER BY c.timestamp DESC LIMIT 3;" 2>/dev/null

echo "=== Monitoring Tamamlandı ==="
EOF

chmod +x /root/logweb/5651-logging/monitor_parser.sh

echo "=== Kurulum Tamamlandı ==="
echo "✅ Dynamic parser servisi kuruldu ve başlatıldı"
echo "📁 Test script'i: /root/logweb/5651-logging/test_dynamic_parser.sh"
echo "📊 Monitoring script'i: /root/logweb/5651-logging/monitor_parser.sh"
echo "📝 Log dosyası: /root/logweb/5651-logging/logs/dynamic_parser.log"
echo "🔧 Servis komutları:"
echo "   systemctl status 5651-dynamic-parser"
echo "   systemctl restart 5651-dynamic-parser"
echo "   systemctl stop 5651-dynamic-parser" 