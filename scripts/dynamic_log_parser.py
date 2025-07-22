#!/usr/bin/env python3
"""
5651 Dynamic Log Parser
Otomatik hotspot algılama ve log işleme
"""

import os
import re
import json
import logging
import psycopg2
import redis
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set
import time

class DynamicLogParser:
    def __init__(self, config_file: str = "config/parser.json"):
        self.config = self.load_config(config_file)
        self.setup_logging()
        self.db_conn = None
        self.redis_conn = None
        self.known_hotspots: Set[str] = set()
        self.processed_files: Set[str] = set()
        
    def load_config(self, config_file: str) -> Dict:
        """Konfigürasyon dosyasını yükle"""
        try:
            with open(config_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Konfigürasyon yükleme hatası: {e}")
            return {}
    
    def setup_logging(self):
        """Logging ayarları"""
        log_dir = Path("logs")
        log_dir.mkdir(exist_ok=True)
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('logs/dynamic_parser.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def get_db_connection(self):
        """PostgreSQL bağlantısı"""
        try:
            if not self.db_conn or self.db_conn.closed:
                db_config = self.config.get('database', {})
                self.db_conn = psycopg2.connect(
                    host=db_config.get('host', 'localhost'),
                    port=db_config.get('port', 5432),
                    database=db_config.get('name', 'loglama_db'),
                    user=db_config.get('user', 'loglama_user'),
                    password=db_config.get('password', 'Zkngnr81.')
                )
            return self.db_conn
        except Exception as e:
            self.logger.error(f"Veritabanı bağlantı hatası: {e}")
            return None
    
    def get_redis_connection(self):
        """Redis bağlantısı"""
        try:
            if not self.redis_conn:
                redis_config = self.config.get('redis', {})
                self.redis_conn = redis.Redis(
                    host=redis_config.get('host', 'localhost'),
                    port=redis_config.get('port', 6379),
                    db=redis_config.get('db', 0)
                )
            return self.redis_conn
        except Exception as e:
            self.logger.error(f"Redis bağlantı hatası: {e}")
            return None
    
    def discover_hotspots(self) -> Set[str]:
        """Yeni hotspot'ları keşfet"""
        log_dirs = self.config.get('log_directories', [])
        current_hotspots = set()
        
        for log_dir in log_dirs:
            if not os.path.exists(log_dir):
                continue
            
            # Tüm hotspot klasörlerini tara
            for item in Path(log_dir).iterdir():
                if item.is_dir():
                    current_hotspots.add(item.name)
        
        # Yeni hotspot'ları bul
        new_hotspots = current_hotspots - self.known_hotspots
        if new_hotspots:
            self.logger.info(f"Yeni hotspot'lar keşfedildi: {new_hotspots}")
            self.known_hotspots.update(new_hotspots)
            
            # Yeni hotspot'ları veritabanına ekle
            for hotspot in new_hotspots:
                self.add_hotspot_to_db(hotspot)
        
        return current_hotspots
    
    def add_hotspot_to_db(self, hotspot_name: str):
        """Yeni hotspot'u veritabanına ekle"""
        conn = self.get_db_connection()
        if not conn:
            return False
        
        try:
            cursor = conn.cursor()
            
            # Hotspot'u ekle
            cursor.execute("""
                INSERT INTO hotspots (name, location, status, created_at)
                VALUES (%s, %s, 'active', NOW())
                ON CONFLICT (name) DO UPDATE SET
                updated_at = NOW(),
                status = 'active'
                RETURNING id
            """, (hotspot_name, hotspot_name))
            
            hotspot_id = cursor.fetchone()[0]
            conn.commit()
            
            self.logger.info(f"Yeni hotspot eklendi: {hotspot_name} (ID: {hotspot_id})")
            return True
            
        except Exception as e:
            self.logger.error(f"Hotspot ekleme hatası {hotspot_name}: {e}")
            conn.rollback()
            return False
    
    def parse_log_line(self, line: str, hotspot_name: str) -> Optional[Dict]:
        """Log satırını parse et"""
        # 5651 log formatı: Jul 22 01:37:54 hotspot-name srcnat: in:INTERFACE out:INTERFACE, connection-state:new src-mac MAC, proto PROTOCOL, IP:PORT->IP:PORT, len SIZE
        pattern = r'(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+([^\s]+)\s+srcnat:\s+in:([^\s]+)\s+out:([^,]+),?\s+connection-state:([^\s,]+),?\s+src-mac\s+([^\s,]+),?\s+proto\s+([^,]+),?\s+([^,]+),?\s+len\s+(\d+)'
        
        match = re.match(pattern, line)
        if not match:
            return None
        
        try:
            # IP adreslerini çıkar
            ip_info = match.group(8)
            ip_pattern = r'(\d+\.\d+\.\d+\.\d+):(\d+)->(\d+\.\d+\.\d+\.\d+):(\d+)'
            ip_match = re.search(ip_pattern, ip_info)
            
            if not ip_match:
                return None
            
            return {
                'timestamp': datetime.strptime(f"{datetime.now().year} {match.group(1)}", "%Y %b %d %H:%M:%S"),
                'hotspot_name': hotspot_name,
                'in_interface': match.group(3),
                'out_interface': match.group(4),
                'connection_state': match.group(5),
                'src_mac': match.group(6),
                'protocol': match.group(7),
                'src_ip': ip_match.group(1),
                'src_port': ip_match.group(2),
                'dst_ip': ip_match.group(3),
                'dst_port': ip_match.group(4),
                'packet_size': int(match.group(9))
            }
        except Exception as e:
            self.logger.error(f"Log parse hatası: {e} - Line: {line}")
            return None
    
    def save_connection_to_db(self, log_data: Dict):
        """Bağlantı verisini veritabanına kaydet"""
        conn = self.get_db_connection()
        if not conn:
            return False
        
        try:
            cursor = conn.cursor()
            
            # Hotspot ID'sini al
            cursor.execute("SELECT id FROM hotspots WHERE name = %s", (log_data['hotspot_name'],))
            result = cursor.fetchone()
            if not result:
                self.logger.error(f"Hotspot bulunamadı: {log_data['hotspot_name']}")
                return False
            
            hotspot_id = result[0]
            
            # Bağlantıyı kaydet
            cursor.execute("""
                INSERT INTO connections (
                    hotspot_id, timestamp, src_ip, dst_ip, src_port, dst_port,
                    protocol, src_mac, connection_state, packet_size, in_interface, out_interface
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                hotspot_id, log_data['timestamp'], log_data['src_ip'], log_data['dst_ip'],
                log_data['src_port'], log_data['dst_port'], log_data['protocol'],
                log_data['src_mac'], log_data['connection_state'], log_data['packet_size'],
                log_data['in_interface'], log_data['out_interface']
            ))
            
            conn.commit()
            return True
            
        except Exception as e:
            self.logger.error(f"Bağlantı kaydetme hatası: {e}")
            conn.rollback()
            return False
    
    def process_log_files(self):
        """Log dosyalarını işle"""
        log_dirs = self.config.get('log_directories', [])
        
        for log_dir in log_dirs:
            if not os.path.exists(log_dir):
                continue
            
            # Her hotspot klasörünü tara
            for hotspot_dir in Path(log_dir).iterdir():
                if not hotspot_dir.is_dir():
                    continue
                
                hotspot_name = hotspot_dir.name
                
                # Log dosyalarını tara
                for log_file in hotspot_dir.glob("*.log"):
                    file_id = f"{hotspot_name}_{log_file.name}_{log_file.stat().st_mtime}"
                    
                    # Dosya daha önce işlendiyse atla
                    if file_id in self.processed_files:
                        continue
                    
                    self.process_single_log_file(log_file, hotspot_name)
                    self.processed_files.add(file_id)
    
    def process_single_log_file(self, log_file: Path, hotspot_name: str):
        """Tek log dosyasını işle"""
        try:
            processed_count = 0
            with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    if not line:
                        continue
                    
                    log_data = self.parse_log_line(line, hotspot_name)
                    if log_data:
                        if self.save_connection_to_db(log_data):
                            processed_count += 1
                    
                    # Her 1000 satırda bir ilerleme göster
                    if line_num % 1000 == 0:
                        self.logger.debug(f"{log_file.name}: {line_num} satır işlendi")
            
            if processed_count > 0:
                self.logger.info(f"{log_file.name}: {processed_count} bağlantı kaydedildi")
                        
        except Exception as e:
            self.logger.error(f"Log dosyası işleme hatası {log_file}: {e}")
    
    def cleanup_old_files(self):
        """Eski işlenmiş dosya kayıtlarını temizle"""
        # 1000'den fazla kayıt varsa en eski 500'ünü sil
        if len(self.processed_files) > 1000:
            self.processed_files = set(list(self.processed_files)[-500:])
    
    def run(self):
        """Ana çalışma döngüsü"""
        self.logger.info("5651 Dynamic Log Parser başlatıldı")
        
        # İlk hotspot keşfi
        self.discover_hotspots()
        
        while True:
            try:
                # Yeni hotspot'ları keşfet
                self.discover_hotspots()
                
                # Log dosyalarını işle
                self.process_log_files()
                
                # Temizlik
                self.cleanup_old_files()
                
                self.logger.info(f"Aktif hotspot'lar: {len(self.known_hotspots)} - İşlenmiş dosyalar: {len(self.processed_files)}")
                
                # 30 saniye bekle
                time.sleep(30)
                
            except KeyboardInterrupt:
                self.logger.info("Kullanıcı tarafından durduruldu")
                break
            except Exception as e:
                self.logger.error(f"Ana döngü hatası: {e}")
                time.sleep(10)

if __name__ == "__main__":
    parser = DynamicLogParser()
    parser.run() 