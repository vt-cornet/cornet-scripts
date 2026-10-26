#!/usr/bin/env bash
# ==============================================================================
# File: remote-desktop/setup-gnome-rdp-system.sh
# Purpose: Automated System-Level GNOME Remote Desktop (RDP) Configuration
# ==============================================================================
# Tested on: Ubuntu 24.04 LTS / Ubuntu 26.04 LTS
#
# What this script does:
#   1. Installs gnome-remote-desktop and dependencies if missing.
#   2. Generates system-wide TLS certificates with explicit daemon ownership.
#   3. Registers configuration via 'grdctl --system' non-interactively.
#   4. Permanently masks/suppresses per-user daemons across all user accounts.
#   5. Enables and restarts the system-wide gnome-remote-desktop service.
#
# Usage:
#   sudo ./setup-gnome-rdp-system.sh <USERNAME> <RDP_PASSWORD>
#
# Example:
#   sudo ./setup-gnome-rdp-system.sh pratheek "MySecurePass123"
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[-] Error: This script must be run as root (or via sudo)." >&2
    exit 1
fi

TARGET_USER="${1:-}"
RDP_PASSWORD="${2:-}"

if [[ -z "$TARGET_USER" || -z "$RDP_PASSWORD" ]]; then
    echo "Usage: $0 <USERNAME> <RDP_PASSWORD>"
    echo ""
    echo "Example:"
    echo "  sudo $0 pratheek 'YourRDPPassword'"
    exit 1
fi

# Verify user exists
if ! id "$TARGET_USER" &>/dev/null; then
    echo "[-] Error: User '$TARGET_USER' does not exist on this system." >&2
    exit 1
fi

echo "[+] Step 1: Installing required packages..."
apt-get update -qq
apt-get install -y -qq gnome-remote-desktop openssl

echo "[+] Step 2: Generating system-wide TLS certificate..."
mkdir -p /etc/gnome-remote-desktop
CERT_PATH="/etc/gnome-remote-desktop/rdp-tls.crt"
KEY_PATH="/etc/gnome-remote-desktop/rdp-tls.key"

openssl req -new -x509 -days 730 -nodes -newkey rsa:2048 \
  -out "$CERT_PATH" \
  -keyout "$KEY_PATH" \
  -subj "/CN=$(hostname)" \
  2>/dev/null

# Ensure system user gnome-remote-desktop owns certificate and key
if id "gnome-remote-desktop" &>/dev/null; then
    chown -R gnome-remote-desktop:gnome-remote-desktop /etc/gnome-remote-desktop
fi
chmod 600 "$KEY_PATH"
chmod 644 "$CERT_PATH"
echo "[✓] TLS certificate generated at $CERT_PATH"

echo "[+] Step 3: Registering system-level RDP settings via grdctl..."
grdctl --system rdp set-tls-cert "$CERT_PATH"
grdctl --system rdp set-tls-key "$KEY_PATH"
grdctl --system rdp set-credentials "$TARGET_USER" "$RDP_PASSWORD"
grdctl --system rdp disable-view-only
grdctl --system rdp enable

echo "[+] Step 4: Permanently suppressing per-user daemon instances..."
# Mask globally for all existing and future user sessions
systemctl --global disable gnome-remote-desktop.service 2>/dev/null || true
systemctl --global mask gnome-remote-desktop.service 2>/dev/null || true

# Stop active per-user instances for logged-in users if running
pkill -u "$TARGET_USER" gnome-remote-desktop-daemon 2>/dev/null || true

echo "[+] Step 5: Enabling and starting system service..."
systemctl daemon-reload
systemctl enable gnome-remote-desktop.service
systemctl restart gnome-remote-desktop.service

# Verification
sleep 2
if systemctl is-active --quiet gnome-remote-desktop.service; then
    echo "[✓] GNOME Remote Desktop system daemon is ACTIVE and running."
    echo "[*] Listening on RDP port 3389 for user: $TARGET_USER"
    echo "[*] Connect with: $(hostname).cornet.wireless.vt.edu:3389"
else
    echo "[!] Warning: Service is not reporting active status. Inspecting journal:"
    journalctl -u gnome-remote-desktop.service -n 15 --no-pager
fi
