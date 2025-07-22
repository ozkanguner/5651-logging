#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
5651 Loglama Sistemi - Web Uygulaması
Flask tabanlı REST API ve web arayüzü
"""

from flask import Flask, request, jsonify, render_template, send_from_directory
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import psycopg2
from psycopg2.extras import RealDictCursor
import redis
import json
import logging
from datetime import datetime, timedelta
import os
from typing import Dict, List, Optional
import requests

# Flask uygulaması
app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', '5651-loglama-secret-key')
app.config['JSON_AS_ASCII'] = False

# CORS etkinleştir
CORS(app)

# Rate limiting
limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"]
)

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Veritabanı bağlantısı
def get_db_connection():
    """PostgreSQL bağlantısı al"""
    try:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST', 'localhost'),
            port=os.environ.get('DB_PORT', '5432'),
            database=os.environ.get('DB_NAME', 'loglama_db'),
            user=os.environ.get('DB_USER', 'loglama_user'),
            password=os.environ.get('DB_PASSWORD', 'loglama123')
        )
        return conn
    except Exception as e:
        logger.error(f"Veritabanı bağlantı hatası: {e}")
        return None

# Redis bağlantısı
def get_redis_connection():
    """Redis bağlantısı al"""
    try:
        redis_url = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')
        return redis.from_url(redis_url)
    except Exception as e:
        logger.error(f"Redis bağlantı hatası: {e}")
        return None

class LoglamaAPI:
    """5651 Loglama API sınıfı"""
    
    def __init__(self):
        self.db_conn = get_db_connection()
        self.redis_conn = get_redis_connection()
    
    def get_hotspots(self) -> List[Dict]:
        """Tüm hotspot'ları getir"""
        try:
            with self.db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute("""
                    SELECT id, name, location, ip_range, status, created_at, updated_at
                    FROM hotspots
                    ORDER BY name
                """)
                return cursor.fetchall()
        except Exception as e:
            logger.error(f"Hotspot listesi alınırken hata: {e}")
            return []
    
    def get_hotspot_statistics(self, hotspot_id: int = None) -> List[Dict]:
        """Hotspot istatistiklerini getir"""
        try:
            with self.db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
                if hotspot_id:
                    cursor.execute("""
                        SELECT * FROM hotspot_statistics WHERE id = %s
                    """, (hotspot_id,))
                else:
                    cursor.execute("SELECT * FROM hotspot_statistics")
                return cursor.fetchall()
        except Exception as e:
            logger.error(f"İstatistik alınırken hata: {e}")
            return []
    
    def get_connections(self, hotspot_id: int = None, limit: int = 100, 
                       start_date: str = None, end_date: str = None) -> List[Dict]:
        """Bağlantı kayıtlarını getir"""
        try:
            with self.db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
                query = """
                    SELECT c.*, h.name as hotspot_name
                    FROM connections c
                    JOIN hotspots h ON c.hotspot_id = h.id
                    WHERE 1=1
                """
                params = []
                
                if hotspot_id:
                    query += " AND c.hotspot_id = %s"
                    params.append(hotspot_id)
                
                if start_date:
                    query += " AND c.timestamp >= %s"
                    params.append(start_date)
                
                if end_date:
                    query += " AND c.timestamp <= %s"
                    params.append(end_date)
                
                query += " ORDER BY c.timestamp DESC LIMIT %s"
                params.append(limit)
                
                cursor.execute(query, params)
                return cursor.fetchall()
        except Exception as e:
            logger.error(f"Bağlantı kayıtları alınırken hata: {e}")
            return []
    
    def get_daily_stats(self, days: int = 30) -> List[Dict]:
        """Günlük istatistikleri getir"""
        try:
            with self.db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute("""
                    SELECT 
                        connection_date,
                        SUM(connection_count) as total_connections,
                        SUM(unique_users) as total_unique_users,
                        SUM(total_bytes) as total_bytes
                    FROM daily_connection_stats
                    WHERE connection_date >= CURRENT_DATE - INTERVAL '%s days'
                    GROUP BY connection_date
                    ORDER BY connection_date DESC
                """, (days,))
                return cursor.fetchall()
        except Exception as e:
            logger.error(f"Günlük istatistikler alınırken hata: {e}")
            return []
    
    def get_user_activity(self, mac_address: str = None) -> List[Dict]:
        """Kullanıcı aktivitelerini getir"""
        try:
            with self.db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
                if mac_address:
                    cursor.execute("""
                        SELECT u.*, h.name as hotspot_name
                        FROM users u
                        JOIN hotspots h ON u.hotspot_id = h.id
                        WHERE u.mac_address = %s
                        ORDER BY u.last_seen DESC
                    """, (mac_address,))
                else:
                    cursor.execute("""
                        SELECT u.*, h.name as hotspot_name
                        FROM users u
                        JOIN hotspots h ON u.hotspot_id = h.id
                        ORDER BY u.last_seen DESC
                        LIMIT 100
                    """)
                return cursor.fetchall()
        except Exception as e:
            logger.error(f"Kullanıcı aktiviteleri alınırken hata: {e}")
            return []
    
    def search_connections(self, search_term: str, limit: int = 100) -> List[Dict]:
        """Bağlantı kayıtlarında arama yap"""
        try:
            with self.db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute("""
                    SELECT c.*, h.name as hotspot_name
                    FROM connections c
                    JOIN hotspots h ON c.hotspot_id = h.id
                    WHERE 
                        c.src_mac ILIKE %s OR
                        c.src_ip::text ILIKE %s OR
                        c.dst_ip::text ILIKE %s OR
                        c.protocol ILIKE %s OR
                        h.name ILIKE %s
                    ORDER BY c.timestamp DESC
                    LIMIT %s
                """, (f'%{search_term}%', f'%{search_term}%', f'%{search_term}%', 
                      f'%{search_term}%', f'%{search_term}%', limit))
                return cursor.fetchall()
        except Exception as e:
            logger.error(f"Arama yapılırken hata: {e}")
            return []

# API instance'ı
api = LoglamaAPI()

# Ana sayfa
@app.route('/')
def index():
    """Ana sayfa"""
    return render_template('index.html')

# API Routes

@app.route('/api/hotspots', methods=['GET'])
@limiter.limit("100 per hour")
def get_hotspots():
    """Tüm hotspot'ları getir"""
    try:
        hotspots = api.get_hotspots()
        return jsonify({
            'success': True,
            'data': hotspots,
            'count': len(hotspots)
        })
    except Exception as e:
        logger.error(f"Hotspot listesi hatası: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/hotspots/<int:hotspot_id>', methods=['GET'])
@limiter.limit("100 per hour")
def get_hotspot(hotspot_id):
    """Belirli bir hotspot'u getir"""
    try:
        with api.db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute("""
                SELECT * FROM hotspots WHERE id = %s
            """, (hotspot_id,))
            hotspot = cursor.fetchone()
            
            if not hotspot:
                return jsonify({
                    'success': False,
                    'error': 'Hotspot bulunamadı'
                }), 404
            
            return jsonify({
                'success': True,
                'data': hotspot
            })
    except Exception as e:
        logger.error(f"Hotspot detay hatası: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/statistics')
def api_statistics():
    conn = get_db_connection()
    cur = conn.cursor()
    # Toplam hotspot sayısı
    cur.execute("SELECT COUNT(*) FROM hotspots;")
    hotspot_count = cur.fetchone()[0]
    # Toplam kullanıcı (benzersiz MAC)
    cur.execute("SELECT COUNT(DISTINCT mac_address) FROM users;")
    unique_users = cur.fetchone()[0]
    # Toplam bağlantı
    cur.execute("SELECT COUNT(*) FROM connections;")
    total_connections = cur.fetchone()[0]
    # Toplam trafik (byte)
    cur.execute("SELECT SUM(packet_size) FROM connections;")
    total_bytes = cur.fetchone()[0] or 0
    return jsonify({
        "success": True,
        "data": [{
            "hotspot_count": hotspot_count,
            "unique_users": unique_users,
            "total_connections": total_connections,
            "total_bytes": total_bytes
        }]
    })

@app.route('/api/protocol-distribution')
def protocol_distribution():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT protocol, COUNT(*) FROM connections GROUP BY protocol;")
    rows = cur.fetchall()
    data = [{"protocol": r[0], "count": r[1]} for r in rows]
    return jsonify({"success": True, "data": data})

@app.route('/api/connections')
def api_connections():
    conn = get_db_connection()
    cur = conn.cursor()
    limit = int(request.args.get('limit', 10))
    cur.execute("""
        SELECT id, hotspot_id, src_ip, src_mac, protocol, timestamp
        FROM connections
        ORDER BY timestamp DESC
        LIMIT %s
    """, (limit,))
    rows = cur.fetchall()
    data = [
        {
            "id": r[0],
            "hotspot_id": r[1],
            "src_ip": r[2],
            "src_mac": r[3],
            "protocol": r[4],
            "timestamp": r[5].isoformat() if r[5] else None
        }
        for r in rows
    ]
    return jsonify({"success": True, "count": len(data), "data": data})

@app.route('/api/users')
def api_users():
    conn = get_db_connection()
    cur = conn.cursor()
    limit = int(request.args.get('limit', 10))
    cur.execute("""
        SELECT id, mac_address, hotspot_id, first_seen, last_seen, total_connections
        FROM users
        ORDER BY last_seen DESC
        LIMIT %s
    """, (limit,))
    rows = cur.fetchall()
    data = [
        {
            "id": r[0],
            "mac_address": r[1],
            "hotspot_id": r[2],
            "first_seen": r[3].isoformat() if r[3] else None,
            "last_seen": r[4].isoformat() if r[4] else None,
            "total_connections": r[5]
        }
        for r in rows
    ]
    return jsonify({"success": True, "count": len(data), "data": data})

@app.route('/api/daily-stats', methods=['GET'])
@limiter.limit("100 per hour")
def get_daily_stats():
    """Günlük istatistikleri getir"""
    try:
        days = request.args.get('days', 30, type=int)
        stats = api.get_daily_stats(days)
        
        return jsonify({
            'success': True,
            'data': stats
        })
    except Exception as e:
        logger.error(f"Günlük istatistik hatası: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/users', methods=['GET'])
@limiter.limit("100 per hour")
def get_users():
    """Kullanıcı aktivitelerini getir"""
    try:
        mac_address = request.args.get('mac_address')
        users = api.get_user_activity(mac_address)
        
        return jsonify({
            'success': True,
            'data': users,
            'count': len(users)
        })
    except Exception as e:
        logger.error(f"Kullanıcı aktiviteleri hatası: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/search', methods=['GET'])
@limiter.limit("50 per hour")
def search():
    """Arama yap"""
    try:
        search_term = request.args.get('q', '')
        limit = request.args.get('limit', 100, type=int)
        
        if not search_term:
            return jsonify({
                'success': False,
                'error': 'Arama terimi gerekli'
            }), 400
        
        results = api.search_connections(search_term, limit)
        
        return jsonify({
            'success': True,
            'data': results,
            'count': len(results),
            'search_term': search_term
        })
    except Exception as e:
        logger.error(f"Arama hatası: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/health', methods=['GET'])
def health_check():
    """Sistem sağlık kontrolü"""
    try:
        # Veritabanı bağlantısını kontrol et
        db_status = "healthy" if api.db_conn else "unhealthy"
        
        # Redis bağlantısını kontrol et
        redis_status = "healthy" if api.redis_conn else "unhealthy"
        
        return jsonify({
            'success': True,
            'status': 'healthy',
            'services': {
                'database': db_status,
                'redis': redis_status
            },
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'status': 'unhealthy',
            'error': str(e)
        }), 500

# Dashboard sayfaları
@app.route('/dashboard')
def dashboard():
    """Dashboard ana sayfası"""
    return render_template('dashboard.html')

@app.route('/dashboard/hotspots')
def hotspots_dashboard():
    """Hotspot dashboard"""
    return render_template('hotspots.html')

@app.route('/dashboard/connections')
def connections_dashboard():
    """Bağlantılar dashboard"""
    return render_template('connections.html')

@app.route('/dashboard/users')
def users_dashboard():
    """Kullanıcılar dashboard"""
    return render_template('users.html')

@app.route('/dashboard/reports')
def reports_dashboard():
    """Raporlar dashboard"""
    return render_template('reports.html')

# Static dosyalar
@app.route('/static/<path:filename>')
def static_files(filename):
    """Static dosyaları serve et"""
    return send_from_directory('static', filename)

# Hata sayfaları
@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'success': False,
        'error': 'Sayfa bulunamadı'
    }), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({
        'success': False,
        'error': 'Sunucu hatası'
    }), 500

if __name__ == '__main__':
    # Geliştirme sunucusu
    app.run(
        host='0.0.0.0',
        port=int(os.environ.get('PORT', 8000)),
        debug=os.environ.get('DEBUG', 'False').lower() == 'true'
    ) 