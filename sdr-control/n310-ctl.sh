#!/usr/bin/env bash
# ==============================================================================
# File: sdr-control/n310-ctl.sh
# Purpose: Ettus USRP N310 Remote Power Control, Detection, and Diagnostics
# ==============================================================================
# Controls and monitors Ettus USRP N300/N310/N320 series SDRs across CORNET.
#
# Background & Architecture:
#   Unlike the X310 (which is an FPGA-only board powered via AC smart plugs),
#   the N310 features an embedded ARM CPU running Linux and a secondary STM32
#   microcontroller for power sequencing and hardware monitoring.
#
#   Cutting power abruptly can corrupt the internal eMMC/SD card filesystem.
#   According to the Ettus Getting Started Guide:
#     - Clean shutdown MUST be issued via SSH/console ('shutdown -h now' or 'systemctl poweroff').
#     - Auto-boot on AC power is configured in EEPROM ('eeprom-set-flags 0x1').
#     - Physical power button presses can be simulated over the STM32 UART console ('powerbtn').
#
# Hardware map:
#   N310 on wvt-wstation3-ubuntu:  IP: 192.168.20.2 (SFP1 enp132s0f1np1), Serial: 3196923, FPGA: XG
#   N310 on wvt-nuc-02:            IP: 192.168.20.2 (SFP1 enp2s0f1np1),   Serial: 319692B, FPGA: WX
#
# Usage:
#   ./n310-ctl.sh status    [IP]
#   ./n310-ctl.sh shutdown  [IP] [-y]
#   ./n310-ctl.sh reboot    [IP] [-y]
#   ./n310-ctl.sh powerbtn  [SERIAL_DEV]
#   ./n310-ctl.sh auto-boot [IP]
#   ./n310-ctl.sh probe     [IP]
# ==============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Default Configuration
# ---------------------------------------------------------------------------
DEFAULT_N310_IP="192.168.20.2"
SSH_USER="root"
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=4"

# ---------------------------------------------------------------------------
# Colors
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

usage() {
    echo -e "${C_BOLD}Usage:${C_RESET} $0 <action> [options]"
    echo ""
    echo -e "  ${C_BOLD}Actions:${C_RESET}"
    echo "    status    [IP]        Check N310 reachability via ping, SSH, and uhd_find_devices"
    echo "    shutdown  [IP] [-y]   Cleanly power off the embedded Linux OS (prevents FS corruption)"
    echo "    reboot    [IP] [-y]   Reboot the N310 ARM CPU and FPGA"
    echo "    powerbtn  [DEV]       Simulate physical power button press via STM32 microcontroller UART"
    echo "    auto-boot [IP]        Enable auto-boot on AC power restore via EEPROM flags (0x1)"
    echo "    probe     [IP]        Execute uhd_usrp_probe to query RF frontend and clock locks"
    echo ""
    echo -e "  ${C_BOLD}Defaults:${C_RESET}"
    echo "    Default Target IP:    ${DEFAULT_N310_IP}"
    echo "    Default SSH User:     ${SSH_USER}"
    echo ""
    echo -e "  ${C_BOLD}Examples:${C_RESET}"
    echo "    $0 status"
    echo "    $0 shutdown 192.168.20.2 -y"
    echo "    $0 auto-boot 192.168.20.2"
    echo "    $0 powerbtn /dev/serial/by-id/usb-Silicon_Labs_CP2105*-if01*"
    exit 1
}

# ---------------------------------------------------------------------------
# Action Implementations
# ---------------------------------------------------------------------------

check_ping() {
    local ip="$1"
    if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

n310_status() {
    local ip="$1"
    echo -e "${C_BOLD}[*] Checking N310 Status at ${ip}...${C_RESET}"

    # 1. Network Ping Check
    if check_ping "$ip"; then
        echo -e "  ${C_GREEN}✓ ICMP Ping:${C_RESET} Device is reachable over network."
    else
        echo -e "  ${C_RED}✗ ICMP Ping:${C_RESET} No network response from ${ip}."
        echo -e "    ${C_DIM}Check interface link status, SFP+ optical connection, or IP routing.${C_RESET}"
        return 1
    fi

    # 2. SSH / Embedded ARM OS Check
    echo -n "  [*] ARM Linux OS: "
    local arm_info
    if arm_info=$(ssh ${SSH_OPTS} "${SSH_USER}@${ip}" "hostname; uname -r; uptime" 2>/dev/null); then
        echo -e "${C_GREEN}ONLINE${C_RESET}"
        local hostname_str kernel uptime_str
        hostname_str=$(echo "$arm_info" | head -n 1)
        kernel=$(echo "$arm_info" | sed -n '2p')
        uptime_str=$(echo "$arm_info" | sed -n '3p' | sed -e 's/^[ \t]*//')
        echo -e "      Hostname: ${hostname_str}"
        echo -e "      Kernel:   ${kernel}"
        echo -e "      Uptime:   ${uptime_str}"
    else
        echo -e "${C_YELLOW}SSH UNREACHABLE (Key authentication required or daemon initializing)${C_RESET}"
    fi

    # 3. UHD Device Detection
    if command -v uhd_find_devices >/dev/null 2>&1; then
        echo -e "  [*] Running uhd_find_devices --args=\"type=n3xx,addr=${ip}\"..."
        local uhd_out
        uhd_out=$(uhd_find_devices --args="type=n3xx,addr=${ip}" 2>&1 || true)
        if echo "$uhd_out" | grep -q "product: n310"; then
            local dev_serial dev_name dev_fpga
            dev_serial=$(echo "$uhd_out" | awk -F': ' '/serial:/ {print $2}' | head -n1)
            dev_name=$(echo "$uhd_out" | awk -F': ' '/name:/ {print $2}' | head -n1)
            dev_fpga=$(echo "$uhd_out" | awk -F': ' '/fpga:/ {print $2}' | head -n1)
            echo -e "      ${C_GREEN}✓ UHD Detected:${C_RESET} Name=${dev_name}, Serial=${dev_serial}, FPGA=${dev_fpga}"
        else
            echo -e "      ${C_YELLOW}UHD query did not return an active N310 device.${C_RESET}"
        fi
    fi
}

n310_shutdown() {
    local ip="$1"
    local force="$2"

    if [ "$force" != "true" ]; then
        echo ""
        echo -e "  ${C_YELLOW}⚠  N310 CLEAN SHUTDOWN WARNING${C_RESET}"
        echo "     This will halt the embedded Linux OS on the N310 (${ip})."
        echo "     Once shut down, the unit enters standby mode."
        echo "     To turn it back on, you must press the power button, cycle AC power (if auto-boot enabled),"
        echo "     or issue 'powerbtn' over the microcontroller UART console."
        echo ""
        read -r -p "  Type 'yes' to confirm shutdown: " confirm
        if [ "$confirm" != "yes" ]; then
            echo "  Aborted."
            exit 0
        fi
    fi

    echo -e "${C_YELLOW}[+] Issuing clean shutdown to N310 at ${ip} via SSH...${C_RESET}"
    if ssh ${SSH_OPTS} "${SSH_USER}@${ip}" "shutdown -h now" 2>/dev/null; then
        echo -e "  ${C_GREEN}✓ Shutdown signal accepted.${C_RESET}"
    else
        # SSH connection closing upon shutdown is expected
        echo -e "  ${C_GREEN}✓ Shutdown initiated (connection terminated by host).${C_RESET}"
    fi

    echo "[*] Waiting for network interface to go down..."
    local count=0
    while check_ping "$ip" && [ $count -lt 15 ]; do
        sleep 1
        count=$((count + 1))
    done

    if check_ping "$ip"; then
        echo -e "  ${C_YELLOW}[!] Device is still responding to ping. Shutdown may take a few more seconds.${C_RESET}"
    else
        echo -e "  ${C_GREEN}[✓] N310 at ${ip} has cleanly shut down.${C_RESET}"
    fi
}

n310_reboot() {
    local ip="$1"
    local force="$2"

    if [ "$force" != "true" ]; then
        echo ""
        echo -e "  ${C_YELLOW}⚠  N310 REBOOT CONFIRMATION${C_RESET}"
        echo "     This will reboot the ARM processor and reload the FPGA on the N310 (${ip})."
        echo ""
        read -r -p "  Type 'yes' to confirm reboot: " confirm
        if [ "$confirm" != "yes" ]; then
            echo "  Aborted."
            exit 0
        fi
    fi

    echo -e "${C_CYAN}[+] Rebooting N310 at ${ip}...${C_RESET}"
    ssh ${SSH_OPTS} "${SSH_USER}@${ip}" "reboot" 2>/dev/null || true
    echo -e "  ${C_GREEN}✓ Reboot signal dispatched.${C_RESET}"
    echo "[*] Device will become available in approximately 30-45 seconds."
}

n310_auto_boot() {
    local ip="$1"
    echo -e "${C_CYAN}[+] Enabling Auto-Boot on AC Power for N310 at ${ip}...${C_RESET}"
    echo "    (Sets MCU EEPROM flag 0x1 so N310 boots automatically when AC power is applied)"

    local output
    if output=$(ssh ${SSH_OPTS} "${SSH_USER}@${ip}" "eeprom-set-flags 0x1" 2>&1); then
        echo -e "  ${C_GREEN}✓ EEPROM flags updated successfully.${C_RESET}"
        echo "$output" | grep -E "MCU_FLAGS|Serial" | sed -e 's/^/    /' || true
    else
        echo -e "  ${C_RED}✗ Failed to update EEPROM flags via SSH.${C_RESET}"
        echo "    $output"
        return 1
    fi
}

n310_probe() {
    local ip="$1"
    echo -e "${C_BOLD}[*] Probing N310 at ${ip} via uhd_usrp_probe...${C_RESET}"
    if ! command -v uhd_usrp_probe >/dev/null 2>&1; then
        echo -e "${C_RED}ERROR: uhd_usrp_probe is not installed on this host.${C_RESET}"
        exit 1
    fi

    uhd_usrp_probe --args="type=n3xx,addr=${ip}"
}

n310_powerbtn() {
    local dev="$1"

    # Auto-detect STM32 serial interface if not passed
    if [ -z "$dev" ]; then
        dev=$(ls -1 /dev/serial/by-id/*-if01* 2>/dev/null | head -n 1 || true)
        if [ -z "$dev" ]; then
            dev=$(ls -1 /dev/ttyUSB1 2>/dev/null || true)
        fi
    fi

    if [ -z "$dev" ] || [ ! -e "$dev" ]; then
        echo -e "${C_RED}ERROR: STM32 Microcontroller serial interface not found.${C_RESET}"
        echo "  The N310 USB console must be plugged into this host via the micro-USB port."
        echo "  If connected, specify the device explicitly, e.g.:"
        echo "    $0 powerbtn /dev/serial/by-id/usb-Silicon_Labs_CP2105*-if01-port0"
        exit 1
    fi

    echo -e "${C_CYAN}[+] Simulating physical power button press via ${dev}...${C_RESET}"

    # Configure serial port baud rate (115200) and send powerbtn command
    if command -v stty >/dev/null 2>&1; then
        stty -F "$dev" 115200 raw -echo 2>/dev/null || true
    fi

    # Send newline, command, and newline to STM32 prompt
    printf "\r\npowerbtn\r\n" > "$dev"
    echo -e "  ${C_GREEN}✓ 'powerbtn' command transmitted to STM32 microcontroller.${C_RESET}"
    echo "  ${C_DIM}The power state transition has been triggered.${C_RESET}"
}

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------
[ $# -lt 1 ] && usage

ACTION="$1"
shift

TARGET_IP="${DEFAULT_N310_IP}"
FORCE=false
SERIAL_DEV=""

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        /dev/*)
            SERIAL_DEV="$1"
            shift
            ;;
        [0-9]*.[0-9]*.[0-9]*.[0-9]*)
            TARGET_IP="$1"
            shift
            ;;
        *)
            TARGET_IP="$1"
            shift
            ;;
    esac
done

case "$ACTION" in
    status)
        n310_status "$TARGET_IP"
        ;;
    shutdown|poweroff)
        n310_shutdown "$TARGET_IP" "$FORCE"
        ;;
    reboot)
        n310_reboot "$TARGET_IP" "$FORCE"
        ;;
    auto-boot|autoboot)
        n310_auto_boot "$TARGET_IP"
        ;;
    probe)
        n310_probe "$TARGET_IP"
        ;;
    powerbtn)
        n310_powerbtn "$SERIAL_DEV"
        ;;
    *)
        echo -e "${C_RED}Unknown action: ${ACTION}${C_RESET}"
        usage
        ;;
esac
