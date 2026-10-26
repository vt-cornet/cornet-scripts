#!/usr/bin/env bash
# ==============================================================================
# File: power/wake-node.sh
# Purpose: Send Wake-on-LAN MagicPacket to CORNET lab nodes/workstations
# ==============================================================================
# Usage:
#   ./wake-node.sh <MAC_ADDRESS_OR_HOSTNAME> [BROADCAST_IP]
#
# Examples:
#   ./wake-node.sh ac:b4:80:3a:3a:9e
#   ./wake-node.sh wvt-wstation1 128.173.94.255
# ==============================================================================

set -euo pipefail

TARGET="${1:-}"
BROADCAST="${2:-255.255.255.255}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <MAC_ADDRESS_OR_HOSTNAME> [BROADCAST_IP]"
    echo ""
    echo "Known Node MAC Addresses:"
    echo "  wvt-pratheek-pc-ubuntu : ac:b4:80:3a:3a:9e"
    echo "  wvt-wstation1-ubuntu   : ac:b4:80:3a:3a:82"
    echo "  wvt-wstation3-ubuntu   : ac:b4:80:3a:3a:51"
    echo "  wvt-nuc-02             : 58:47:ca:7c:1d:75"
    exit 1
fi

# Resolve hostname to MAC if a known alias was passed
case "${TARGET,,}" in
    wvt-pratheek-pc*|pratheek-pc) MAC="ac:b4:80:3a:3a:9e" ;;
    wvt-wstation1*|wstation1)     MAC="ac:b4:80:3a:3a:82" ;;
    wvt-wstation3*|wstation3)     MAC="ac:b4:80:3a:3a:51" ;;
    wvt-nuc-02*|nuc-02|nuc2)      MAC="58:47:ca:7c:1d:75" ;;
    *)                            MAC="$TARGET" ;;
esac


echo "[+] Sending Wake-on-LAN MagicPacket to ${MAC} (broadcast: ${BROADCAST})..."

if command -v wakeonlan &>/dev/null; then
    wakeonlan -i "$BROADCAST" "$MAC"
elif command -v etherwake &>/dev/null; then
    etherwake -b "$MAC"
else
    # Native python fallback if wakeonlan/etherwake are not installed
    python3 -c "
import socket
mac = '$MAC'.replace(':', '').replace('-', '')
if len(mac) != 12:
    raise ValueError('Invalid MAC address length')
data = bytes.fromhex('FF' * 6 + mac * 16)
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.sendto(data, ('$BROADCAST', 9))
print('[✓] MagicPacket sent successfully via Python.')
"
fi
