#!/bin/bash
# =============================================================================
# CORNET DDNS Node Registration Script
# =============================================================================
# Registers a new lab node / workstation in the DDNS whitelist and DNS backend.
#
# Can be run directly inside LXC 200, or from cornet-node01 (auto-detects pct).
#
# Usage:
#   ./register-node.sh <HOSTNAME> [INITIAL_IP]
#
# Examples:
#   ./register-node.sh wvt-gnuc-03
#   ./register-node.sh wvt-gnuc-03 128.173.94.103
# =============================================================================

set -euo pipefail

HOSTNAME_INPUT="${1:-}"
INITIAL_IP="${2:-}"

if [[ -z "$HOSTNAME_INPUT" ]]; then
    echo "Usage: $0 <HOSTNAME> [INITIAL_IP]"
    echo ""
    echo "Examples:"
    echo "  $0 wvt-gnuc-03"
    echo "  $0 wvt-gnuc-03 128.173.94.103"
    exit 1
fi

# Sanitize hostname (strip domain if passed, lowercase)
HOSTNAME_CLEAN=$(echo "$HOSTNAME_INPUT" | sed 's/\.cornet\.wireless\.vt\.edu//g' | tr '[:upper:]' '[:lower:]')

# Validate hostname format
if [[ ! "$HOSTNAME_CLEAN" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
    echo "[ERROR] Invalid hostname '$HOSTNAME_CLEAN'. Must be lowercase alphanumeric with hyphens." >&2
    exit 1
fi

# Validate IP if provided
if [[ -n "$INITIAL_IP" ]]; then
    if [[ ! "$INITIAL_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "[ERROR] Invalid IPv4 address '$INITIAL_IP'." >&2
        exit 1
    fi
fi

# Detect environment: Inside container 200 or on Proxmox host
if command -v pct &>/dev/null && pct status 200 &>/dev/null; then
    RUN_PREFIX="pct exec 200 --"
    echo "[INFO] Running via Proxmox LXC 200 container bridge..."
else
    RUN_PREFIX=""
fi

echo "[INFO] Registering node: '${HOSTNAME_CLEAN}'..."

# 1. Update ALLOWED_HOSTNAMES in /opt/ddns-api/app.py
$RUN_PREFIX python3 -c "
import re, sys

app_path = '/opt/ddns-api/app.py'
hostname = '${HOSTNAME_CLEAN}'

with open(app_path, 'r') as f:
    content = f.read()

# Check if already present
pattern = re.compile(r\"ALLOWED_HOSTNAMES\s*=\s*\[(.*?)\]\", re.DOTALL)
match = pattern.search(content)
if not match:
    print('[ERROR] Could not find ALLOWED_HOSTNAMES in app.py', file=sys.stderr)
    sys.exit(1)

hostnames_block = match.group(1)
if f\"'{hostname}'\" in hostnames_block or f'\"{hostname}\"' in hostnames_block:
    print(f'[INFO] Hostname {hostname} is already in ALLOWED_HOSTNAMES.')
else:
    # Insert new hostname before the closing bracket
    new_entry = f\"    '{hostname}',\n]\"
    new_content = content[:match.end() - 1] + f\"    '{hostname}',\n\" + content[match.end() - 1:]
    with open(app_path, 'w') as f:
        f.write(new_content)
    print(f'[SUCCESS] Added {hostname} to ALLOWED_HOSTNAMES.')
"

# 2. If INITIAL_IP is supplied, update /etc/dnsmasq.conf
if [[ -n "$INITIAL_IP" ]]; then
    $RUN_PREFIX python3 -c "
import re

dnsmasq_path = '/etc/dnsmasq.conf'
hostname = '${HOSTNAME_CLEAN}'
ip = '${INITIAL_IP}'
domain = 'cornet.wireless.vt.edu'
fqdn = f'{hostname}.{domain}'

with open(dnsmasq_path, 'r') as f:
    content = f.read()

pattern = f'address=/{fqdn}/'
if pattern in content:
    new_content = re.sub(
        f'address=/{re.escape(fqdn)}/[0-9.]+',
        f'address=/{fqdn}/{ip}',
        content
    )
    print(f'[INFO] Updated existing dnsmasq entry for {fqdn} -> {ip}')
else:
    new_content = content + f'\naddress=/{fqdn}/{ip}\n'
    print(f'[SUCCESS] Appended new dnsmasq entry for {fqdn} -> {ip}')

with open(dnsmasq_path, 'w') as f:
    f.write(new_content)
"
fi

# 3. Restart Services
echo "[INFO] Restarting ddns-api and dnsmasq services..."
$RUN_PREFIX systemctl restart ddns-api
if [[ -n "$INITIAL_IP" ]]; then
    $RUN_PREFIX systemctl restart dnsmasq
fi

# 4. Verify Health
STATUS=$($RUN_PREFIX curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/health || echo "failed")
if [[ "$STATUS" == "200" ]]; then
    echo "[SUCCESS] DDNS API is healthy (HTTP 200). Node '${HOSTNAME_CLEAN}' is successfully registered!"
else
    echo "[WARN] Service restarted, but health probe returned HTTP ${STATUS}."
fi
