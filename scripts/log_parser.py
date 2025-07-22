#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
5651 Loglama Sistemi - Log Parser
Bu script, hotspot loglarını parse eder ve veritabanına kaydeder.
"""

import re
import json
import logging
import argparse
from datetime import datetime
from typing import Dict, Optional, List
import psycopg2
from psycopg2.extras import RealDictCursor
import redis
from elasticsearch import Elasticsearch

# Logging konfigürasyonu
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/5651-loglama/logs/parser.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class LogParser:
    """5651 loglama sistemi için log parser sınıfı"""
    
    def __init__(self, config: Dict):
        """Parser'ı başlat"""
        self.config = config
        self.log_pattern = re.compile(
            r'(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+'  # Tarih/saat
            r'([^\s]+)\s+'  # Hotspot adı
            r'srcnat:\s+'  # İşlem türü
            r'in:([^\s]+)\s+'  # Giriş interface
            r'out:([^\s,]+),?\s+'  # Çıkış interface
            r'connection-state:([^\s,]+),?\s+'  # Bağlantı durumu
            r'src-mac\s+([^\s,]+),?\s+'  # MAC adresi
            r'proto\s+([^,]+),\s+'  # Protokol
            r'([^,]+),\s+'  # IP bilgileri
            r'len\s+(\d+)'  # Paket boyutu
        )
        
        # Veritabanı bağlantıları
        self.db_conn = None
        self.redis_conn = None
        self.es_client = None
        
        self._init_connections()
    
    def _init_connections(self):
        """Veritabanı bağlantılarını başlat"""
        try:
            # PostgreSQL bağlantısı
            self.db_conn = psycopg2.connect(
                host=self.config['postgres']['host'],
                port=self.config['postgres']['port'],
                database=self.config['postgres']['database'],
                user=self.config['postgres']['user'],
                password=self.config['postgres']['password']
            )
            
            # Redis bağlantısı
            self.redis_conn = redis.Redis(
                host=self.config['redis']['host'],
                port=self.config['redis']['port'],
                db=self.config['redis']['db']
            )
            
            # Elasticsearch bağlantısı
            self.es_client = Elasticsearch([
                {'host': self.config['elasticsearch']['host'],
                 'port': self.config['elasticsearch']['port']}
            ])
            
            logger.info("Veritabanı bağlantıları başarıyla kuruldu")
            
        except Exception as e:
            logger.error(f"Veritabanı bağlantı hatası: {e}")
            raise
    
    def parse_log_line(self, line: str) -> Optional[Dict]:
        """Tek bir log satırını parse et"""
        try:
            match = self.log_pattern.match(line.strip())
            if not match:
                logger.warning(f"Log satırı parse edilemedi: {line}")
                return None
            
            # Match gruplarını al
            groups = match.groups()
            
            # Tarih/saat bilgisini parse et
            timestamp_str = f"{datetime.now().year} {groups[0]}"
            timestamp = datetime.strptime(timestamp_str, "%Y %b %d %H:%M:%S")
            
            # IP bilgilerini parse et
            ip_info = groups[7]
            ip_match = re.search(r'(\d+\.\d+\.\d+\.\d+):(\d+)->(\d+\.\d+\.\d+\.\d+):(\d+)', ip_info)
            
            if not ip_match:
                logger.warning(f"IP bilgileri parse edilemedi: {ip_info}")
                return None
            
            parsed_data = {
                'timestamp': timestamp,
                'hotspot_name': groups[1],
                'in_interface': groups[2],
                'out_interface': groups[3],
                'connection_state': groups[4],
                'src_mac': groups[5],
                'protocol': groups[6],
                'src_ip': ip_match.group(1),
                'src_port': int(ip_match.group(2)),
                'dst_ip': ip_match.group(3),
                'dst_port': int(ip_match.group(4)),
                'packet_size': int(groups[8]),
                'raw_line': line.strip()
            }
            
            return parsed_data
            
        except Exception as e:
            logger.error(f"Log parsing hatası: {e}, Satır: {line}")
            return None
    
    def save_to_postgresql(self, data: Dict):
        """Veriyi PostgreSQL'e kaydet"""
        try:
            with self.db_conn.cursor() as cursor:
                # Hotspot'u kontrol et/ekle
                cursor.execute("""
                    INSERT INTO hotspots (name, created_at, status)
                    VALUES (%s, %s, 'active')
                    ON CONFLICT (name) DO NOTHING
                    RETURNING id
                """, (data['hotspot_name'], data['timestamp']))
                
                hotspot_result = cursor.fetchone()
                if hotspot_result:
                    hotspot_id = hotspot_result[0]
                else:
                    cursor.execute("SELECT id FROM hotspots WHERE name = %s", (data['hotspot_name'],))
                    hotspot_id = cursor.fetchone()[0]
                
                # Bağlantı kaydını ekle
                cursor.execute("""
                    INSERT INTO connections (
                        hotspot_id, timestamp, src_mac, src_ip, src_port,
                        dst_ip, dst_port, protocol, packet_size, connection_state,
                        in_interface, out_interface, raw_line
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    hotspot_id, data['timestamp'], data['src_mac'], data['src_ip'],
                    data['src_port'], data['dst_ip'], data['dst_port'], data['protocol'],
                    data['packet_size'], data['connection_state'], data['in_interface'],
                    data['out_interface'], data['raw_line']
                ))
                
                # Kullanıcı kaydını güncelle
                cursor.execute("""
                    INSERT INTO users (mac_address, hotspot_id, first_seen, last_seen, total_connections)
                    VALUES (%s, %s, %s, %s, 1)
                    ON CONFLICT (mac_address, hotspot_id) DO UPDATE SET
                        last_seen = EXCLUDED.last_seen,
                        total_connections = users.total_connections + 1
                """, (data['src_mac'], hotspot_id, data['timestamp'], data['timestamp']))
                
                self.db_conn.commit()
                
        except Exception as e:
            logger.error(f"PostgreSQL kaydetme hatası: {e}")
            self.db_conn.rollback()
            raise
    
    def save_to_elasticsearch(self, data: Dict):
        """Veriyi Elasticsearch'e kaydet"""
        try:
            doc = {
                'timestamp': data['timestamp'].isoformat(),
                'hotspot_name': data['hotspot_name'],
                'src_mac': data['src_mac'],
                'src_ip': data['src_ip'],
                'dst_ip': data['dst_ip'],
                'protocol': data['protocol'],
                'packet_size': data['packet_size'],
                'connection_state': data['connection_state'],
                'in_interface': data['in_interface'],
                'out_interface': data['out_interface']
            }
            
            self.es_client.index(
                index=f"5651-loglama-{data['timestamp'].strftime('%Y.%m.%d')}",
                body=doc
            )
            
        except Exception as e:
            logger.error(f"Elasticsearch kaydetme hatası: {e}")
    
    def cache_connection(self, data: Dict):
        """Bağlantı bilgisini Redis'e cache'le"""
        try:
            cache_key = f"connection:{data['src_mac']}:{data['timestamp'].strftime('%Y%m%d%H%M%S')}"
            self.redis_conn.setex(cache_key, 3600, json.dumps(data))  # 1 saat TTL
            
        except Exception as e:
            logger.error(f"Redis cache hatası: {e}")
    
    def process_log_file(self, file_path: str):
        """Log dosyasını işle"""
        try:
            logger.info(f"Log dosyası işleniyor: {file_path}")
            
            with open(file_path, 'r', encoding='utf-8') as file:
                for line_num, line in enumerate(file, 1):
                    if line.strip():
                        parsed_data = self.parse_log_line(line)
                        if parsed_data:
                            try:
                                self.save_to_postgresql(parsed_data)
                                self.save_to_elasticsearch(parsed_data)
                                self.cache_connection(parsed_data)
                                
                                if line_num % 1000 == 0:
                                    logger.info(f"{line_num} satır işlendi")
                                    
                            except Exception as e:
                                logger.error(f"Satır {line_num} işlenirken hata: {e}")
                                continue
            
            logger.info(f"Log dosyası tamamlandı: {file_path}")
            
        except Exception as e:
            logger.error(f"Log dosyası işleme hatası: {e}")
            raise
    
    def close(self):
        """Bağlantıları kapat"""
        if self.db_conn:
            self.db_conn.close()
        if self.redis_conn:
            self.redis_conn.close()

def load_config(config_path: str) -> Dict:
    """Konfigürasyon dosyasını yükle"""
    try:
        with open(config_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Konfigürasyon yükleme hatası: {e}")
        raise

def main():
    """Ana fonksiyon"""
    parser = argparse.ArgumentParser(description='5651 Loglama Sistemi - Log Parser')
    parser.add_argument('--config', default='/opt/5651-loglama/config/parser.json',
                       help='Konfigürasyon dosyası yolu')
    parser.add_argument('--file', required=True, help='İşlenecek log dosyası')
    parser.add_argument('--dry-run', action='store_true', help='Test modu')
    
    args = parser.parse_args()
    
    try:
        # Konfigürasyonu yükle
        config = load_config(args.config)
        
        # Parser'ı başlat
        log_parser = LogParser(config)
        
        if args.dry_run:
            logger.info("Test modu - dosya işlenmeyecek")
            # Test için sadece ilk 10 satırı parse et
            with open(args.file, 'r') as f:
                for i, line in enumerate(f):
                    if i >= 10:
                        break
                    parsed = log_parser.parse_log_line(line)
                    if parsed:
                        print(json.dumps(parsed, indent=2, default=str))
        else:
            # Gerçek işleme
            log_parser.process_log_file(args.file)
        
        log_parser.close()
        logger.info("İşlem tamamlandı")
        
    except Exception as e:
        logger.error(f"Ana işlem hatası: {e}")
        exit(1)

if __name__ == "__main__":
    main() 