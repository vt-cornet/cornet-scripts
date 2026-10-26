#!/usr/bin/env bash
# ==============================================================================
# File: power/enable-wol.sh
# Purpose: Auto-detect default ethernet interface and configure persistent WoL
# ==============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "[-] Error: Run as root or with sudo."; exit 1; }

echo "[+] Detecting primary network interface..."
PRIMARY_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1)

if [[ -z "$PRIMARY_IFACE" ]]; then
  echo "[-] Failed to detect default network interface."
  exit 1
fi

echo "[*] Target interface: ${PRIMARY_IFACE}"

# Verify ethtool is available
if ! command -v ethtool &>/dev/null; then
  echo "[+] Installing ethtool..."
  apt-get update -qq && apt-get install -y -qq ethtool
fi

# Check WoL capability
WOL_SUPPORT=$(ethtool "${PRIMARY_IFACE}" 2>/dev/null | grep -i "Supports Wake-on:" || true)
echo "[*] Interface capabilities: ${WOL_SUPPORT}"

if [[ "$WOL_SUPPORT" != *"g"* ]]; then
  echo "[!] Warning: Interface ${PRIMARY_IFACE} does not advertise MagicPacket ('g') support."
  echo "    Ensure Wake-on-LAN / PCIe Wake is enabled in the BIOS/UEFI."
fi

# Apply immediately
echo "[+] Enabling MagicPacket WoL on ${PRIMARY_IFACE}..."
ethtool -s "${PRIMARY_IFACE}" wol g

# Make persistent via systemd-networkd link file
mkdir -p /etc/systemd/network
LINK_FILE="/etc/systemd/network/10-wol-${PRIMARY_IFACE}.link"
echo "[+] Writing persistent link rule to ${LINK_FILE}..."
cat <<EOF > "${LINK_FILE}"
[Match]
OriginalName=${PRIMARY_IFACE}

[Link]
WakeOnLan=magic
EOF

# Make persistent via NetworkManager (if NetworkManager is active)
if command -v nmcli &>/dev/null && systemctl is-active --quiet NetworkManager; then
  CON_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep ":${PRIMARY_IFACE}$" | cut -d: -f1 || true)
  if [[ -n "$CON_NAME" ]]; then
    echo "[+] Configuring NetworkManager connection: ${CON_NAME}"
    nmcli connection modify "$CON_NAME" 802-3-ethernet.wake-on-lan magic 2>/dev/null || true
  fi
fi

# Verify status
CURRENT_WOL=$(ethtool "${PRIMARY_IFACE}" | grep -i "Wake-on:" | tr -d '\t')
echo "[✓] Configuration complete: ${CURRENT_WOL}"
MAC_ADDR=$(ip link show "${PRIMARY_IFACE}" | awk '/ether/ {print $2}')
echo "[*] Node MAC address for wake scripts: ${MAC_ADDR}"
