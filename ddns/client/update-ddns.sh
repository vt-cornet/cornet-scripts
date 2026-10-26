#!/bin/bash
# =============================================================================
# CORNET DDNS Update Script - Hardened Multi-Interface Workstation Client
# =============================================================================
# Runs once on boot via systemd cornet-ddns.service
# Updates dnsmasq on dns-server container (198.82.18.150) via Flask API
# =============================================================================

set -uo pipefail

HOSTNAME="${DDNS_HOSTNAME:-$(hostname -s)}"
API_URL="${DDNS_API_URL:-http://198.82.18.150:5000/update}"
API_HOST="${DDNS_API_HOST:-198.82.18.150}"
TOKEN="${DDNS_TOKEN:-c156174195be0621f574b3fc11ed815f0c41b6cf2f51ddc6b512d3ed01f1ee96}"
LOG_FILE="${DDNS_LOG_FILE:-/opt/cornet/ddns-update.log}"

mkdir -p "$(dirname "$LOG_FILE")"

for attempt in 1 2 3 4 5; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # 1. Resolve source IP and device actively routing to DDNS API host
    ROUTE_INFO=$(ip route get "$API_HOST" 2>/dev/null || true)
    CURRENT_IP=$(echo "$ROUTE_INFO" | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    CURRENT_DEV=$(echo "$ROUTE_INFO" | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')

    # 2. Check if route exists
    if [ -z "$CURRENT_IP" ] || [ -z "$CURRENT_DEV" ]; then
        echo "$TIMESTAMP - Attempt $attempt: No route to $API_HOST yet, retrying..." >> "$LOG_FILE"
        sleep 5
        continue
    fi

    # 3. Guard against Wi-Fi interfaces
    if [[ "$CURRENT_DEV" =~ ^wl ]]; then
        echo "$TIMESTAMP - Attempt $attempt: Route is on Wi-Fi ($CURRENT_DEV). Waiting for Ethernet..." >> "$LOG_FILE"
        sleep 5
        continue
    fi

    # 4. Guard against local/smart-plug LANs (e.g. GL.iNet router subnets)
    if [[ "$CURRENT_IP" == 192.168.* || "$CURRENT_IP" == 10.* || "$CURRENT_IP" == 172.16.* ]]; then
        echo "$TIMESTAMP - Attempt $attempt: Resolved to private LAN IP ($CURRENT_IP on $CURRENT_DEV). Retrying..." >> "$LOG_FILE"
        sleep 5
        continue
    fi

    # 5. Push update to API with 5-second max execution timeout
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{\"hostname\":\"$HOSTNAME\",\"ip\":\"$CURRENT_IP\",\"token\":\"$TOKEN\"}")

    if [ "$RESPONSE" = "200" ]; then
        echo "$TIMESTAMP - Updated $HOSTNAME -> $CURRENT_IP via $CURRENT_DEV (attempt $attempt)" >> "$LOG_FILE"
        echo "Updated: $CURRENT_IP via $CURRENT_DEV"
        exit 0
    fi

    echo "$TIMESTAMP - Attempt $attempt: API returned HTTP $RESPONSE, retrying..." >> "$LOG_FILE"
    sleep 5
done

echo "$TIMESTAMP - Failed to update after 5 attempts (last HTTP $RESPONSE)" >> "$LOG_FILE"
echo "Failed: HTTP $RESPONSE"
exit 1
