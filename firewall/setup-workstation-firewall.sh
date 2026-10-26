#!/bin/bash
# =============================================================================
# CORNET Workstation Firewall Setup Script (UFW)
# =============================================================================
# Configures host firewall rules on Ubuntu lab workstations to match the
# cluster security model deployed on wvt-nuc-02 and wvt-wstation3-ubuntu.
#
# Policies:
#   - Default: DROP incoming, ACCEPT outgoing
#   - Allow SSH (22/tcp) and RDP (3389/tcp) ONLY from approved campus/VPN subnets
#   - Allow all traffic on Tailscale interface (tailscale0) if present
#   - Allow all traffic on dedicated USRP SDR interfaces
#
# Usage:
#   sudo ./setup-workstation-firewall.sh [OPTIONAL_SDR_INTERFACES...]
# =============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root (or via sudo)." >&2
    exit 1
fi

# 10 approved subnets from cluster.fw IPSET
APPROVED_SUBNETS=(
    "128.173.52.0/24"          # Lab / Department Subnet
    "128.173.88.0/21"          # Campus Node Subnet
    "172.27.0.0/16"            # Internal Lab Subnet
    "172.29.0.0/16"            # Internal Lab Subnet
    "172.30.0.0/16"            # Internal Lab Subnet
    "198.82.18.128/26"         # CORNET Cluster Subnet
    "198.82.8.0/21"            # Virginia Tech Campus VPN Subnet
    "45.3.120.0/22"            # Approved External / VPN Range
    "45.3.124.0/23"            # Approved External / VPN Range
    "45.3.126.0/23"            # Approved External / VPN Range
)

echo "[INFO] Configuring default UFW policies..."
ufw default deny incoming
ufw default allow outgoing

# Remove any wide-open generic SSH / RDP rules to ensure subnet restrictions
echo "[INFO] Removing generic allow rules for SSH/RDP if present..."
ufw delete allow 22/tcp 2>/dev/null || true
ufw delete allow 3389/tcp 2>/dev/null || true

echo "[INFO] Adding approved subnet access for SSH (22) and RDP (3389)..."
for subnet in "${APPROVED_SUBNETS[@]}"; do
    ufw allow from "$subnet" to any port 22 proto tcp comment "SSH from approved subnet"
    ufw allow from "$subnet" to any port 3389 proto tcp comment "RDP from approved subnet"
done

# Tailscale interface rule
if ip link show tailscale0 &>/dev/null; then
    echo "[INFO] Detected tailscale0. Allowing in on tailscale0..."
    ufw allow in on tailscale0 comment "Allow all Tailscale traffic"
fi

# USRP SDR interfaces: auto-detect or allow command line arguments
SDR_IFACES=("$@")
if [[ ${#SDR_IFACES[@]} -eq 0 ]]; then
    # Auto-detect Mellanox / high-speed SDR interfaces (e.g. *f0np0, *f1np1, or enp47s0)
    for dev in $(ip -o link show | awk -F': ' '{print $2}' | grep -E 'f[0-9]+np[0-9]+$|^enp47s0$'); do
        SDR_IFACES+=("$dev")
    done
fi

for iface in "${SDR_IFACES[@]}"; do
    if ip link show "$iface" &>/dev/null; then
        echo "[INFO] Allowing all traffic on USRP SDR interface: $iface..."
        ufw allow in on "$iface" comment "Allow USRP SDR interface"
    fi
done

echo "[INFO] Enabling UFW..."
ufw --force enable
ufw reload

echo "[SUCCESS] UFW firewall configuration complete:"
ufw status numbered
