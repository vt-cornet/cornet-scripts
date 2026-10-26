#!/bin/bash
# x310-ctl — CORNET X310 Smart Plug Power Control (Colorized)
# ==========================================================
# Controls AC power to Ettus USRP X310 SDRs via Shelly Gen4 smart plugs.
#
# Hardware map:
#   X310 #1  ->  Shelly Plug 1 (192.168.8.50, MAC: AC:EB:E6:F5:1F:60)  ->  wvt-nuc-02
#   X310 #2  ->  Shelly Plug 2 (192.168.8.51, MAC: AC:EB:E6:F3:D1:74)  ->  wvt-wstation3-ubuntu
#
# Usage:
#   x310-ctl status [1|2|all]
#   x310-ctl on     [1|2|all]
#   x310-ctl off    [1|2|all] [-y]
#   x310-ctl cycle  [1|2|all] [-y]

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PLUG1_IP="192.168.8.50"   # X310 #1 — wvt-nuc-02
PLUG2_IP="192.168.8.51"   # X310 #2 — wvt-wstation3

CURL_TIMEOUT=5            # seconds before giving up on an HTTP request
CYCLE_WAIT=10             # seconds between off and on during a power cycle

# ---------------------------------------------------------------------------
# Colors (Auto-detects TTY)
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_RED="\033[1;31m"
    C_GREEN="\033[1;32m"
    C_YELLOW="\033[1;33m"
    C_BLUE="\033[1;34m"
    C_CYAN="\033[1;36m"
    C_DIM="\033[2m"
else
    C_RESET=""
    C_BOLD=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
    C_DIM=""
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { echo -e "${C_RED}ERROR: $*${C_RESET}" >&2; exit 1; }

check_deps() {
    command -v curl >/dev/null 2>&1 || die "curl not found. Run: sudo apt install curl"
    command -v jq   >/dev/null 2>&1 || die "jq not found.   Run: sudo apt install jq"
}

usage() {
    echo -e "${C_BOLD}Usage:${C_RESET} x310-ctl {status|on|off|cycle} [1|2|all] [-y|--yes]"
    echo ""
    echo "  Targets:   1         = X310 #1 (wvt-nuc-02)"
    echo "             2         = X310 #2 (wvt-wstation3-ubuntu)"
    echo "             all       = both simultaneously (default)"
    echo "  Options:   -y, --yes = Bypass confirmation prompt for off/cycle"
    exit 1
}

shelly_rpc() {
    local ip="$1"
    local method="$2"
    local params="$3"

    local body
    body=$(printf '{"id":1,"method":"%s","params":%s}' "$method" "$params")

    local response
    if ! response=$(curl -sf \
            --connect-timeout "$CURL_TIMEOUT" \
            -X POST \
            -H 'Content-Type: application/json' \
            -d "$body" \
            "http://${ip}/rpc" 2>/dev/null); then
        echo "UNREACHABLE"
        return 1
    fi

    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        echo "RPC ERROR: $(echo "$response" | jq -r '.error.message')" >&2
        return 1
    fi

    echo "$response"
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
plug_on() {
    local ip="$1" id="$2"
    echo -e "${C_CYAN}Powering ON X310 #${id}${C_RESET} via plug at ${ip}..."
    local res
    if ! res=$(shelly_rpc "$ip" "Switch.Set" '{"id":0,"on":true}'); then
        echo -e "  [X310 #${id}] ${C_RED}ERROR: Could not reach plug at ${ip}. Is the router up?${C_RESET}"
        return 0
    fi
    echo -e "  [X310 #${id}] ${C_GREEN}✓ Relay closed.${C_RESET}"
    echo -e "  [X310 #${id}] ${C_DIM}NOTE: Boot takes ~20-30s before FPGA is reachable via UHD.${C_RESET}"
}

plug_off() {
    local ip="$1" id="$2"
    echo -e "${C_YELLOW}Powering OFF X310 #${id}${C_RESET} via plug at ${ip}..."
    local res
    if ! res=$(shelly_rpc "$ip" "Switch.Set" '{"id":0,"on":false}'); then
        echo -e "  [X310 #${id}] ${C_RED}ERROR: Could not reach plug at ${ip}. Is the router up?${C_RESET}"
        return 0
    fi
    echo -e "  [X310 #${id}] ${C_RED}✓ Relay opened. AC power disconnected.${C_RESET}"
}

plug_status() {
    local ip="$1" id="$2"
    local res
    if ! res=$(shelly_rpc "$ip" "Switch.GetStatus" '{"id":0}'); then
        printf "  ${C_BOLD}X310 #%-2s${C_RESET} (%s): ${C_RED}UNREACHABLE — plug not responding${C_RESET}\n" "$id" "$ip"
        return 0
    fi

    local result output apower voltage
    result=$(echo "$res" | jq '.result')
    output=$(echo "$result" | jq -r '.output')
    apower=$(echo "$result" | jq -r '.apower // "N/A"')
    voltage=$(echo "$result" | jq -r '.voltage // "N/A"')

    local relay_str
    if [ "$output" = "true" ]; then
        relay_str="${C_GREEN}ON ${C_RESET}"
    else
        relay_str="${C_DIM}OFF${C_RESET}"
    fi

    printf "  ${C_BOLD}X310 #%-2s${C_RESET} (%s): relay=%b  power=%-8s  voltage=%sV\n" \
        "$id" "$ip" "$relay_str" "${apower}W" "$voltage"

    if [ "$output" = "true" ] && [ "$apower" != "N/A" ]; then
        local apower_int
        apower_int=$(echo "$apower" | cut -d. -f1)
        if [ "$apower_int" -lt 10 ] 2>/dev/null; then
            echo -e "  [X310 #${id}] ${C_YELLOW}WARNING: Relay is ON but draw is ${apower}W — X310 may be in standby.${C_RESET}"
        fi
    fi
}

plug_cycle() {
    local ip="$1" id="$2"
    plug_off "$ip" "$id"
    echo -e "  [X310 #${id}] Waiting ${CYCLE_WAIT}s for DC rail bleed..."
    sleep "$CYCLE_WAIT"
    plug_on "$ip" "$id"
}

confirm_poweroff() {
    if [ "${FORCE_YES:-false}" = "true" ]; then
        return 0
    fi
    echo ""
    echo -e "  ${C_YELLOW}⚠  POWER-OFF WARNING${C_RESET}"
    echo "     This will cut AC power to the selected X310 unit(s)."
    echo "     Ensure no active RF transmission or uhd_image_loader flash is running."
    echo ""
    read -r -p "  Type 'yes' to confirm power-off: " confirm
    if [ "$confirm" != "yes" ]; then
        echo "  Aborted."
        exit 0
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Main Argument Parsing
# ---------------------------------------------------------------------------
check_deps

ACTION=""
TARGET="all"
FORCE_YES=false

for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            FORCE_YES=true
            ;;
        on|off|cycle|status)
            ACTION="$arg"
            ;;
        1|2|all)
            TARGET="$arg"
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${C_RED}Unknown argument: $arg${C_RESET}"
            usage
            ;;
    esac
done

[ -z "$ACTION" ] && usage

if [ "$ACTION" = "off" ] || [ "$ACTION" = "cycle" ]; then
    confirm_poweroff
fi

run_action() {
    local ip="$1" id="$2"
    case "$ACTION" in
        on)     plug_on     "$ip" "$id" ;;
        off)    plug_off    "$ip" "$id" ;;
        cycle)  plug_cycle  "$ip" "$id" ;;
        status) plug_status "$ip" "$id" ;;
    esac
}

echo ""
case "$TARGET" in
    1)
        run_action "$PLUG1_IP" 1
        ;;
    2)
        run_action "$PLUG2_IP" 2
        ;;
    all)
        run_action "$PLUG1_IP" 1 &
        pid1=$!
        run_action "$PLUG2_IP" 2 &
        pid2=$!
        wait "$pid1" "$pid2"
        ;;
esac
echo ""
