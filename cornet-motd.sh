#!/bin/bash
# =============================================================================
# CORNET Cluster MOTD Script
# Installed to: /etc/update-motd.d/99-cornet-motd
# =============================================================================

# Colors
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'

# Node info
HOSTNAME=$(hostname)
PVE_VERSION=$(pveversion 2>/dev/null | cut -d'/' -f2 || echo "unknown")

# Detect IP — try vmbr0 first, then any active interface, then fall back gracefully
get_ip() {
    local IP

    # Try vmbr0 first (primary management bridge)
    IP=$(ip addr show vmbr0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [[ -n "$IP" ]]; then
        echo "$IP"
        return
    fi

    # Try any other active non-loopback interface
    IP=$(ip addr show 2>/dev/null \
        | grep -v "lo\|vmbr\|fwbr\|fwpr\|tap\|veth" \
        | grep "inet " \
        | awk '{print $2}' \
        | cut -d/ -f1 \
        | head -n1)
    if [[ -n "$IP" ]]; then
        echo "$IP"
        return
    fi

    # No IP found
    echo ""
}

IP=$(get_ip)

if [[ -n "$IP" ]]; then
    GUI_URL="https://$IP:8006"
else
    GUI_URL="Unavailable — node may not be connected to the network"
fi

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║           CORNET Research Testbed — Virginia Tech            ║${RESET}"
echo -e "${CYAN}${BOLD}║              Wireless @ VT / Bradley Department              ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${WHITE}${BOLD}  Node:${RESET}     $HOSTNAME"
echo -e "${WHITE}${BOLD}  PVE:${RESET}      $PVE_VERSION"
echo -e "${WHITE}${BOLD}  GUI:${RESET}      $GUI_URL"
echo ""
echo -e "${YELLOW}${BOLD}  ┌─ Documentation ──────────────────────────────────────────┐${RESET}"
echo -e "${YELLOW}${BOLD}  │${RESET}  https://vt-cornet-docs.vercel.app                       ${YELLOW}${BOLD}│${RESET}"
echo -e "${YELLOW}${BOLD}  └──────────────────────────────────────────────────────────┘${RESET}"
echo ""
echo -e "${RED}${BOLD}  ⚠  WARNING: Restricted System${RESET}"
echo -e "  This system is for authorized CORNET personnel only."
echo -e "  Unauthorized access is strictly prohibited and may be"
echo -e "  subject to disciplinary or legal action per VT policy."
echo ""
echo -e "${WHITE}${BOLD}  ┌─ Contacts ────────────────────────────────────────────────┐${RESET}"
echo -e "${WHITE}${BOLD}  │${RESET}  Faculty:       Dr. Carl Dietrich  cdietric@vt.edu         ${WHITE}${BOLD}│${RESET}"
echo -e "${WHITE}${BOLD}  │${RESET}  Administrator: Pratheek Upadhyaya pratheek@vt.edu          ${WHITE}${BOLD}│${RESET}"
echo -e "${WHITE}${BOLD}  │${RESET}  Personnel:     Rahul Varma        crahulvarma@vt.edu       ${WHITE}${BOLD}│${RESET}"
echo -e "${WHITE}${BOLD}  │${RESET}  Personnel:     Souradeep Deb      souradeepdeb@vt.edu      ${WHITE}${BOLD}│${RESET}"
echo -e "${WHITE}${BOLD}  └──────────────────────────────────────────────────────────┘${RESET}"
echo ""
