#!/bin/bash
# =============================================================================
# CORNET Proxmox Node Setup Script
# =============================================================================
# Run this script on every node immediately after joining the cluster.
# Tested on: Proxmox VE 8.4, Ceph Quincy (17.x)
#
# What this script does:
#   1. Disables enterprise repositories
#   2. Adds no-subscription repositories (PVE + Ceph Quincy)
#   3. Runs a full system update
#   4. Suppresses the subscription popup in the web UI
#   5. Installs a dpkg hook to reapply the popup fix after Proxmox updates
#
# Usage:
#   bash <(curl -s https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/node-setup.sh)
#
# Or if running locally:
#   bash node-setup.sh
# =============================================================================

set -euo pipefail

# --- Color output helpers ----------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

# --- Root check --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root."
fi

# --- Proxmox check -----------------------------------------------------------
if ! command -v pveversion &>/dev/null; then
    error "This script must be run on a Proxmox VE node."
fi

# =============================================================================
# STEP 1 — Disable Enterprise Repositories
# =============================================================================
section "Step 1: Disabling Enterprise Repositories"

PVE_ENTERPRISE="/etc/apt/sources.list.d/pve-enterprise.list"
CEPH_ENTERPRISE="/etc/apt/sources.list.d/ceph.list"

if [[ -f "$PVE_ENTERPRISE" ]]; then
    sed -i 's|^deb|#deb|g' "$PVE_ENTERPRISE"
    info "Disabled PVE enterprise repository."
else
    warn "PVE enterprise list not found — skipping."
fi

if [[ -f "$CEPH_ENTERPRISE" ]]; then
    sed -i 's|^deb|#deb|g' "$CEPH_ENTERPRISE"
    info "Disabled Ceph enterprise repository."
else
    warn "Ceph enterprise list not found — skipping."
fi

# =============================================================================
# STEP 2 — Add No-Subscription Repositories
# =============================================================================
section "Step 2: Adding No-Subscription Repositories"

PVE_NOSUB="/etc/apt/sources.list.d/pve-no-subscription.list"
CEPH_NOSUB="/etc/apt/sources.list.d/ceph-no-subscription.list"

# PVE no-subscription repo
if grep -q "pve-no-subscription" "$PVE_NOSUB" 2>/dev/null; then
    info "PVE no-subscription repository already present — skipping."
else
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
        > "$PVE_NOSUB"
    info "Added PVE no-subscription repository."
fi

# Ceph Quincy no-subscription repo
if grep -q "ceph-quincy" "$CEPH_NOSUB" 2>/dev/null; then
    info "Ceph Quincy no-subscription repository already present — skipping."
else
    echo "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription" \
        > "$CEPH_NOSUB"
    info "Added Ceph Quincy no-subscription repository."
fi

# =============================================================================
# STEP 3 — System Update
# =============================================================================
section "Step 3: Running System Update"

info "Updating package lists..."
apt-get update -qq

info "Upgrading packages (this may take a few minutes)..."
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"

info "System update complete."

# =============================================================================
# STEP 4 — Suppress Subscription Popup
# =============================================================================
section "Step 4: Suppressing Subscription Popup"

suppress_popup() {
    local JS_FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

    if [[ ! -f "$JS_FILE" ]]; then
        warn "proxmoxlib.js not found — skipping popup suppression."
        return
    fi

    # Check if already patched
    if grep -q "cornet_patched" "$JS_FILE"; then
        info "Popup suppression already applied — skipping."
        return
    fi

    # Backup original
    cp "$JS_FILE" "${JS_FILE}.bak"

    # Apply patch — short-circuits the subscription check (Proxmox 8.4 syntax)
    sed -i "s|res.data.status.toLowerCase() !== 'active'|res.data.status.toLowerCase() !== 'active' \&\& false /* cornet_patched */|g" "$JS_FILE"

    if grep -q "cornet_patched" "$JS_FILE"; then
        info "Subscription popup suppressed successfully."
    else
        warn "Patch may not have applied correctly. Check $JS_FILE manually."
        # Restore backup if patch failed
        cp "${JS_FILE}.bak" "$JS_FILE"
    fi
}

suppress_popup

# =============================================================================
# STEP 5 — Install dpkg Hook to Reapply Popup Fix After Updates
# =============================================================================
section "Step 5: Installing dpkg Hook for Popup Fix Persistence"

HOOK_DIR="/etc/apt/apt.conf.d"
HOOK_FILE="$HOOK_DIR/99cornet-popup-fix"

cat > "$HOOK_FILE" << 'HOOK'
// Reapply subscription popup suppression after proxmox-widget-toolkit updates
DPkg::Post-Invoke {
    "if dpkg -l proxmox-widget-toolkit 2>/dev/null | grep -q '^ii'; then \
        JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; \
        if [ -f \"$JS\" ] && ! grep -q 'cornet_patched' \"$JS\"; then \
            sed -i \"s|res.data.status.toLowerCase() !== 'active'|res.data.status.toLowerCase() !== 'active' \&\& false /* cornet_patched */|g\" \"$JS\"; \
        fi; \
    fi";
};
HOOK

info "dpkg hook installed at $HOOK_FILE."
info "Popup fix will be automatically reapplied after Proxmox updates."

# =============================================================================
# DONE
# =============================================================================
section "Setup Complete"

info "Node setup finished successfully."
info "Please restart the pveproxy service to apply the popup fix:"
echo ""
echo "    systemctl restart pveproxy"
echo ""
info "Then refresh your browser and verify the subscription popup is gone."
