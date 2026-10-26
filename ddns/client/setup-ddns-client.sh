#!/usr/bin/env bash
# ==============================================================================
# File: ddns/client/setup-ddns-client.sh
# Purpose: One-line automated client setup for CORNET Dynamic DNS (Ubuntu/Debian)
# ==============================================================================
# Usage:
#   sudo ./setup-ddns-client.sh [OPTIONAL_CUSTOM_HOSTNAME]
#
# Or direct one-line install:
#   curl -sSL https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/ddns/client/setup-ddns-client.sh | sudo bash
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[-] Error: This script must be run as root (or via sudo)." >&2
    exit 1
fi

CUSTOM_HOSTNAME="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

echo "[+] Step 1: Preparing /opt/cornet directory..."
mkdir -p /opt/cornet

echo "[+] Step 2: Installing update-ddns.sh..."
if [[ -f "${SCRIPT_DIR}/update-ddns.sh" ]]; then
    cp "${SCRIPT_DIR}/update-ddns.sh" /opt/cornet/update-ddns.sh
else
    # Fallback to downloading directly from GitHub main branch
    curl -sSL -o /opt/cornet/update-ddns.sh \
        "https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/ddns/client/update-ddns.sh"
fi
chmod +x /opt/cornet/update-ddns.sh

# Configure optional custom hostname override if passed
if [[ -n "$CUSTOM_HOSTNAME" ]]; then
    echo "[+] Configuring hostname override: ${CUSTOM_HOSTNAME}..."
    cat <<EOF > /etc/default/cornet-ddns
DDNS_HOSTNAME="${CUSTOM_HOSTNAME}"
EOF
fi

echo "[+] Step 3: Installing systemd boot service..."
cat <<'EOF' > /etc/systemd/system/cornet-ddns.service
[Unit]
Description=CORNET DDNS Update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-/etc/default/cornet-ddns
ExecStart=/bin/bash /opt/cornet/update-ddns.sh
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Step 4: Enabling systemd unit..."
systemctl daemon-reload
systemctl enable cornet-ddns.service

echo "[+] Step 5: Executing immediate registration test..."
if /opt/cornet/update-ddns.sh; then
    echo "[✓] Registration successful! Hostname is registered with CORNET DDNS."
    echo "[*] Systemd service will automatically update DNS on every system boot."
else
    echo "[!] Warning: Initial registration test failed. Check /opt/cornet/ddns-update.log."
fi
