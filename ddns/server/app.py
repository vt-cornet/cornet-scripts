import os
import re
import subprocess
import logging
from flask import Flask, request, jsonify

app = Flask(__name__)

# Configure logging
LOG_FILE = os.environ.get('DDNS_LOG_FILE', '/var/log/ddns-api.log')
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Configuration
# Default token can be overridden via DDNS_TOKEN environment variable
TOKEN = os.environ.get('DDNS_TOKEN', 'YOUR_DDNS_SECRET_TOKEN_HERE')
DNSMASQ_CONF = os.environ.get('DNSMASQ_CONF', '/etc/dnsmasq.conf')
DOMAIN = os.environ.get('DDNS_DOMAIN', 'cornet.wireless.vt.edu')

# Whitelist of allowed hostnames (only authorized machines can register)
ALLOWED_HOSTNAMES = [
    'wvt465-xeon',
    'wvt-pratheek-pc-win',
    'wvt-pratheek-pc-ubuntu',
    'wvt-wstation2-win',
    'wvt-wstation2-ubuntu',
    'wvt-wstation1-win',
    'wvt-wstation1-ubuntu',
    'wvt-nuc-01',
    'wvt-nuc-02',
    'wvt-gnuc-02',
    'wvt-gnuc-05',
    'wvt-wsalpha',
    'wvt-propsim',
    'wvt-wstation3-ubuntu',
    'cornet-rustdesk',
    'wvt-headscale',
]

def is_valid_ip(ip: str) -> bool:
    """Validate IPv4 address format and octet ranges."""
    pattern = r'^(\d{1,3}\.){3}\d{1,3}$'
    if not re.match(pattern, ip):
        return False
    return all(0 <= int(part) <= 255 for part in ip.split('.'))

def update_dnsmasq(hostname: str, ip: str) -> None:
    """Update or insert dnsmasq address entry and restart dnsmasq service."""
    full_hostname = f"{hostname}.{DOMAIN}"
    with open(DNSMASQ_CONF, 'r') as f:
        content = f.read()

    # Check if entry exists
    pattern = f"address=/{full_hostname}/"
    if pattern in content:
        # Update existing entry
        new_content = re.sub(
            f"address=/{re.escape(full_hostname)}/[0-9.]+",
            f"address=/{full_hostname}/{ip}",
            content
        )
    else:
        # Add new entry
        new_content = content + f"\naddress=/{full_hostname}/{ip}\n"

    with open(DNSMASQ_CONF, 'w') as f:
        f.write(new_content)

    # Restart dnsmasq via sudo (permitted in sudoers)
    subprocess.run(
        ['sudo', '/bin/systemctl', 'restart', 'dnsmasq'],
        check=True
    )

@app.route('/health', methods=['GET'])
def health():
    """Health check probe endpoint."""
    return jsonify({'status': 'ok'}), 200

@app.route('/update', methods=['POST'])
def update():
    """Update dynamic DNS record for authorized hostnames."""
    data = request.get_json()

    # Validate request body
    if not data:
        return jsonify({'error': 'Invalid request'}), 400

    # Validate token
    if data.get('token') != TOKEN:
        logging.warning(f"Invalid token from {request.remote_addr}")
        return jsonify({'error': 'Unauthorized'}), 403

    # Validate hostname against whitelist
    hostname = data.get('hostname', '').strip()
    if hostname not in ALLOWED_HOSTNAMES:
        logging.warning(f"Invalid hostname: {hostname} from {request.remote_addr}")
        return jsonify({'error': 'Invalid hostname'}), 400

    # Validate IP address
    ip = data.get('ip', '').strip()
    if not is_valid_ip(ip):
        logging.warning(f"Invalid IP: {ip} from {request.remote_addr}")
        return jsonify({'error': 'Invalid IP address'}), 400

    # Update dnsmasq
    try:
        update_dnsmasq(hostname, ip)
        logging.info(f"Updated {hostname}.{DOMAIN} -> {ip}")
        return jsonify({
            'status': 'ok',
            'hostname': f"{hostname}.{DOMAIN}",
            'ip': ip
        }), 200
    except Exception as e:
        logging.error(f"Failed to update {hostname}: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
