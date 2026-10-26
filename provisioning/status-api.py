#!/usr/bin/env python3
# ==============================================================================
# File: provisioning/status-api.py
# Purpose: Subiquity Autoinstall Status Webhook Receiver
# ==============================================================================
# Deployed to: LXC 210 (198.82.18.151) at /opt/status-api.py
# Systemd unit: /etc/systemd/system/status-api.service
# Port: 5001/tcp (restricted via 210.fw to +approved-subnets)
#
# Receives real-time stage-transition webhooks from the Ubuntu Subiquity installer:
#   reporting.cornet.endpoint: http://198.82.18.151:5001/install-status/<hostname>
# ==============================================================================

from flask import Flask, request
import logging

app = Flask(__name__)

logging.basicConfig(
    filename='/var/log/install-status.log',
    level=logging.INFO,
    format='%(asctime)s - %(message)s'
)

@app.route('/install-status/<hostname>', methods=['POST'])
def status(hostname):
    data = request.get_data(as_text=True)
    logging.info(f"{hostname}: {data}")
    return '', 200

if __name__ == '__main__':
    # Bind to 0.0.0.0 so routed traffic from target subnets is accepted
    app.run(host='0.0.0.0', port=5001)
