import json
import math
import sqlite3
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer

import bcrypt

DB_FILE = 'server_hazards.db'


def init_db():
    db = sqlite3.connect(DB_FILE)
    db.execute(
        'CREATE TABLE IF NOT EXISTS hazards ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'lat REAL, '
        'lng REAL, '
        'timestamp TEXT, '
        'impact REAL, '
        'hit_count INTEGER DEFAULT 1, '
        "hazard_type TEXT DEFAULT 'pothole', "
        'UNIQUE(timestamp, lat, lng)'
        ')'
    )
    db.execute(
        'CREATE TABLE IF NOT EXISTS users ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'email TEXT UNIQUE NOT NULL, '
        'name TEXT NOT NULL, '
        'password_hash TEXT NOT NULL'
        ')'
    )
    try:
        db.execute('ALTER TABLE hazards ADD COLUMN hit_count INTEGER DEFAULT 1')
    except sqlite3.OperationalError:
        pass
    try:
        db.execute("ALTER TABLE hazards ADD COLUMN hazard_type TEXT DEFAULT 'pothole'")
    except sqlite3.OperationalError:
        pass
    db.commit()
    db.close()


def get_local_ip():
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(('8.8.8.8', 80))
        ip = sock.getsockname()[0]
        sock.close()
        return ip
    except OSError:
        try:
            return socket.gethostbyname(socket.gethostname())
        except OSError:
            return '127.0.0.1'


def distance_meters(lat1, lng1, lat2, lng2):
    radius = 6371000.0
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlng / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return radius * c


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _send_json(self, code, data):
        body = json.dumps(data).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get('Content-Length', '0'))
        raw = self.rfile.read(length) if length > 0 else b''
        try:
            return json.loads(raw.decode('utf-8')), None
        except json.JSONDecodeError:
            return None, 'invalid_json'

    def do_POST(self):
        if self.path == '/api/register':
            payload, err = self._read_body()
            if err:
                self._send_json(400, {'status': err})
                return
            email = (payload.get('email') or '').strip().lower()
            name = (payload.get('name') or '').strip()
            password = payload.get('password') or ''
            if not email or not name or not password:
                self._send_json(400, {'status': 'missing_fields'})
                return
            db = sqlite3.connect(DB_FILE)
            try:
                hash_text = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
                db.execute(
                    'INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)',
                    (email, name, hash_text),
                )
                db.commit()
                print(f'Registered: {email}')
                self._send_json(200, {'status': 'registered', 'email': email, 'name': name})
            except sqlite3.IntegrityError:
                self._send_json(409, {'status': 'email_taken'})
            finally:
                db.close()
            return

        if self.path == '/api/login':
            payload, err = self._read_body()
            if err:
                self._send_json(400, {'status': err})
                return
            email = (payload.get('email') or '').strip().lower()
            password = payload.get('password') or ''
            if not email or not password:
                self._send_json(400, {'status': 'missing_fields'})
                return
            db = sqlite3.connect(DB_FILE)
            cur = db.cursor()
            cur.execute(
                'SELECT name, password_hash FROM users WHERE email = ?',
                (email,),
            )
            row = cur.fetchone()
            db.close()
            if row and bcrypt.checkpw(password.encode('utf-8'), row[1].encode('utf-8')):
                print(f'Login OK: {email}')
                self._send_json(200, {'status': 'ok', 'email': email, 'name': row[0]})
            else:
                self._send_json(401, {'status': 'invalid_credentials'})
            return

        if self.path != '/api/sync':
            self._send_json(404, {'status': 'not_found'})
            return
        length = int(self.headers.get('Content-Length', '0'))
        raw = self.rfile.read(length) if length > 0 else b''
        try:
            payload = json.loads(raw.decode('utf-8'))
        except json.JSONDecodeError:
            self._send_json(400, {'status': 'invalid_json'})
            return
        if not isinstance(payload, list):
            self._send_json(400, {'status': 'invalid_payload'})
            return
        db = sqlite3.connect(DB_FILE)
        cur = db.cursor()
        cur.execute('SELECT id, lat, lng, hit_count, hazard_type FROM hazards')
        rows = cur.fetchall()
        saved = 0
        for item in payload:
            if not isinstance(item, dict):
                continue
            lat = item.get('lat')
            lng = item.get('lng')
            timestamp = item.get('timestamp')
            impact = item.get('impact')
            if impact is None:
                impact = item.get('impactMagnitude')
            hazard_type = item.get('hazard_type', 'pothole')
            if lat is None or lng is None or timestamp is None or impact is None:
                continue
            matched = False
            for index, row in enumerate(rows):
                row_id, row_lat, row_lng, row_hits, row_type = row
                if distance_meters(lat, lng, row_lat, row_lng) <= 15.0 and hazard_type == row_type:
                    hits = row_hits if isinstance(row_hits, int) else 1
                    hits += 1
                    new_lat = (row_lat + lat) / 2.0
                    new_lng = (row_lng + lng) / 2.0
                    cur.execute(
                        'UPDATE hazards SET lat = ?, lng = ?, hit_count = ? WHERE id = ?',
                        (new_lat, new_lng, hits, row_id),
                    )
                    rows[index] = (row_id, new_lat, new_lng, hits, row_type)
                    matched = True
                    break
            if matched:
                continue
            cur.execute(
                'INSERT INTO hazards (lat, lng, timestamp, impact, hit_count, hazard_type) VALUES (?, ?, ?, ?, ?, ?)',
                (lat, lng, timestamp, impact, 1, hazard_type),
            )
            rows.append((cur.lastrowid, lat, lng, 1, hazard_type))
            saved += 1
        db.commit()
        db.close()
        print(f'Received {len(payload)} hazards, saved {saved}')
        self._send_json(200, {'status': 'success', 'synced': saved})

    def do_GET(self):
        if self.path != '/api/hazards':
            self._send_json(404, {'status': 'not_found'})
            return
        db = sqlite3.connect(DB_FILE)
        cur = db.cursor()
        cur.execute('SELECT lat, lng, timestamp, impact, hit_count, hazard_type FROM hazards')
        rows = cur.fetchall()
        db.close()
        data = [
            {
                'lat': row[0],
                'lng': row[1],
                'timestamp': row[2],
                'impact': row[3],
                'hit_count': row[4],
                'hazard_type': row[5],
            }
            for row in rows
        ]
        self._send_json(200, data)


def main():
    init_db()
    ip = get_local_ip()
    server = HTTPServer(('0.0.0.0', 3000), Handler)
    print('Server is running on port 3000...')
    print(f'Type this IP in settings: {ip}')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nShutting down the server safely... Goodbye!')
        server.server_close()


if __name__ == '__main__':
    main()