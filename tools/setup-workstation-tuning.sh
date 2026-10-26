#!/usr/bin/env bash
# ==============================================================================
# File: tools/setup-workstation-tuning.sh
# Purpose: Workstation Kernel, Power, Network, and Time Sync Hardening
# ==============================================================================
# Automated system tuning for CORNET Ubuntu lab workstations (Kelly Hall).
#
# Tasks automated:
#   1. Sleep & Suspend Masking:
#      - Completely masks sleep.target, suspend.target, hibernate.target, hybrid-sleep.target.
#      - Configures /etc/systemd/sleep.conf to disallow sleep states.
#      - Disables GNOME/GDM screen idle timeouts and AC sleep.
#   2. Auto-Reboot on Kernel Panic:
#      - Sets kernel.panic = 10 in /etc/sysctl.d/99-panic.conf so headless nodes reboot
#        automatically rather than freezing indefinitely on PCIe NIC/SDR driver faults.
#   3. Network Time Protocol (Chrony) with Virginia Tech Authoritative NTP:
#      - Configures chrony to peer with VT Stratum-2 servers (198.82.247.66 / 198.82.247.98)
#        for sub-microsecond clock synchronization required by O-RAN, 5G, and OctoClock.
#   4. SDR Kernel & Network Socket Buffer Optimization:
#      - Sets net.core socket buffers (rmem_max/wmem_max = 64MB) in /etc/sysctl.d/99-uhd.conf
#        to prevent UHD overflow 'O' and drop 'D' errors during high sample-rate streaming.
#      - Expands 10GbE NIC ring buffers (rx 4096, tx 4096) for all detected SDR interfaces.
#      - Installs a persistent systemd unit to reapply ring buffer tuning on boot.
#
# Usage:
#   sudo ./setup-workstation-tuning.sh
# ==============================================================================

set -euo pipefail

# --- Color Helpers -----------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_RED="\033[1;31m"
    C_GREEN="\033[1;32m"
    C_YELLOW="\033[1;33m"
    C_CYAN="\033[1;36m"
else
    C_RESET=""
    C_BOLD=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_CYAN=""
fi

info()    { echo -e "  ${C_GREEN}✓${C_RESET} $1"; }
step()    { echo -e "\n${C_BOLD}${C_CYAN}[+] $1${C_RESET}"; }
warn()    { echo -e "  ${C_YELLOW}⚠${C_RESET} $1"; }
error()   { echo -e "${C_RED}ERROR:${C_RESET} $1" >&2; exit 1; }

# --- Root Check --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (or via sudo)."
fi

# ==============================================================================
# STEP 1: Complete Sleep and Suspend Masking
# ==============================================================================
step "Step 1: Masking System Sleep, Suspend, and Hibernate Targets"

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1
info "Masked systemd sleep, suspend, hibernate, and hybrid-sleep targets."

# Configure systemd-sleep explicitly
mkdir -p /etc/systemd/sleep.conf.d
cat <<'EOF' > /etc/systemd/sleep.conf.d/99-disable-sleep.conf
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
EOF
info "Installed /etc/systemd/sleep.conf.d/99-disable-sleep.conf"

# Disable GNOME / GDM idle timeouts if GDM is present
if id "gdm" &>/dev/null && command -v gsettings &>/dev/null; then
    sudo -u gdm dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    info "Disabled GDM power timeouts and screen idle delays."
fi

# ==============================================================================
# STEP 2: Auto-Reboot on Kernel Panic
# ==============================================================================
step "Step 2: Configuring Auto-Reboot on Kernel Panic"

cat <<'EOF' > /etc/sysctl.d/99-panic.conf
# Automatically reboot 10 seconds after kernel panic
kernel.panic = 10
kernel.panic_on_oops = 1
EOF
sysctl -p /etc/sysctl.d/99-panic.conf >/dev/null 2>&1
info "Configured kernel.panic = 10 in /etc/sysctl.d/99-panic.conf."

# ==============================================================================
# STEP 3: Network Time Protocol (Chrony) with Virginia Tech NTP
# ==============================================================================
step "Step 3: Configuring High-Precision NTP Synchronization (Chrony)"

if ! command -v chronyd &>/dev/null; then
    echo "  [*] Installing chrony..."
    apt-get update -qq
    apt-get install -y -qq chrony
fi

CHRONY_CONF="/etc/chrony/chrony.conf"
# Check if VT servers are already defined
if ! grep -q "198.82.247.66" "$CHRONY_CONF" 2>/dev/null; then
    # Prepend Virginia Tech Authoritative Stratum-2 NTP servers
    TMP_CHRONY=$(mktemp)
    cat <<'EOF' > "$TMP_CHRONY"
# Virginia Tech Authoritative Stratum-2 NTP Servers (CORNET Campus Time)
server 198.82.247.66 iburst prefer
server 198.82.247.98 iburst

EOF
    cat "$CHRONY_CONF" >> "$TMP_CHRONY"
    mv "$TMP_CHRONY" "$CHRONY_CONF"
    info "Added VT Stratum-2 servers (198.82.247.66, 198.82.247.98) to chrony.conf."
else
    info "VT Stratum-2 servers already configured in chrony.conf."
fi

systemctl enable chrony >/dev/null 2>&1
systemctl restart chrony
info "Restarted chrony service."

# ==============================================================================
# STEP 4: SDR Kernel & Network Socket Buffer Optimization
# ==============================================================================
step "Step 4: Tuning Kernel Socket Buffers for High-Rate SDR Streaming"

# Write Ettus recommended socket buffers
cat <<'EOF' > /etc/sysctl.d/99-uhd.conf
# Ettus USRP High-Rate Streaming Socket Buffer Optimization
# Prevents packet drops ('D') and buffer overflows ('O') on 10GbE/SFP+ links
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432
EOF
sysctl -p /etc/sysctl.d/99-uhd.conf >/dev/null 2>&1
info "Applied 64MB socket buffers in /etc/sysctl.d/99-uhd.conf."

# ==============================================================================
# STEP 5: Expand 10GbE Ring Buffers (rx 4096, tx 4096)
# ==============================================================================
step "Step 5: Optimizing 10GbE Network Ring Buffers"

if ! command -v ethtool &>/dev/null; then
    apt-get install -y -qq ethtool
fi

# Identify dedicated SDR interfaces (match Mellanox/Intel PCI function/port naming)
SDR_IFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -E 'f[0-9]+np[0-9]+$|^enp47s0$' || true)

RING_TUNE_SCRIPT="/usr/local/bin/tune-sdr-interfaces"
cat <<'EOF' > "$RING_TUNE_SCRIPT"
#!/usr/bin/env bash
# Auto-tune ring buffers and MTU on SDR 10GbE interfaces
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E 'f[0-9]+np[0-9]+$|^enp47s0$'); do
    # Expand hardware ring descriptors to 4096
    ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
    # Ensure MTU 9000 if interface is UP
    ip link set dev "$iface" mtu 9000 2>/dev/null || true
done
EOF
chmod +x "$RING_TUNE_SCRIPT"
info "Created $RING_TUNE_SCRIPT"

# Execute tuning immediately for current session
bash "$RING_TUNE_SCRIPT"
info "Applied rx 4096 tx 4096 to active SDR interfaces."

# Install persistent systemd service for ring buffer tuning on boot
cat <<'EOF' > /etc/systemd/system/cornet-sdr-ringbuffers.service
[Unit]
Description=CORNET 10GbE SDR Ring Buffer Optimization
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tune-sdr-interfaces
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cornet-sdr-ringbuffers.service >/dev/null 2>&1
info "Enabled persistent boot service: cornet-sdr-ringbuffers.service"

# ==============================================================================
# Verification Summary
# ==============================================================================
echo ""
echo -e "${C_BOLD}${C_GREEN}=== Tuning Verification Summary ===${C_RESET}"
echo "  [*] Sleep status:     $(systemctl is-enabled sleep.target 2>/dev/null || echo 'masked')"
echo "  [*] Panic timeout:    $(sysctl -n kernel.panic)s"
echo "  [*] rmem_max:         $(sysctl -n net.core.rmem_max) bytes"
echo "  [*] wmem_max:         $(sysctl -n net.core.wmem_max) bytes"
if command -v chronyc &>/dev/null; then
    echo "  [*] Chrony status:    $(systemctl is-active chrony)"
fi
if [[ -n "$SDR_IFACES" ]]; then
    for iface in $SDR_IFACES; do
        local_rx=$(ethtool -g "$iface" 2>/dev/null | awk '/RX:/ {print $2}' | tail -n 1 || echo 'N/A')
        echo "  [*] Ring buffer (${iface}): RX=${local_rx}"
    done
fi
echo -e "${C_GREEN}[✓] System tuning and hardening successfully applied.${C_RESET}\n"
