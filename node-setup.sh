#!/bin/bash
# =============================================================================
# CORNET Proxmox Node Setup Script
# =============================================================================
# Run this script on every node immediately after joining the cluster.
# Tested on: Proxmox VE 8.4, Ceph Quincy (17.x)
#
# What this script does:
#   1. Disables enterprise repositories
#   2. Removes duplicate pve-no-subscription entry from /etc/apt/sources.list
#   3. Adds no-subscription repositories (PVE + Ceph Quincy)
#   4. Runs a full system update
#   5. Suppresses the subscription popup in the web UI
#   6. Installs a helper script + dpkg hook to reapply popup fix after updates
#   7. Installs the CORNET MOTD
#   8. Verifies apt configuration is clean
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
NC='\033[0m'

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
# STEP 2 — Remove Duplicate pve-no-subscription from /etc/apt/sources.list
# =============================================================================
section "Step 2: Cleaning Up Duplicate Repository Entries"

MAIN_SOURCES="/etc/apt/sources.list"

if grep -q "^deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" "$MAIN_SOURCES"; then
    sed -i '/^deb http:\/\/download.proxmox.com\/debian\/pve bookworm pve-no-subscription/d' "$MAIN_SOURCES"
    info "Removed duplicate pve-no-subscription entry from sources.list."
else
    info "No duplicate pve-no-subscription entry found — skipping."
fi

# =============================================================================
# STEP 3 — Add No-Subscription Repositories
# =============================================================================
section "Step 3: Adding No-Subscription Repositories"

PVE_NOSUB="/etc/apt/sources.list.d/pve-no-subscription.list"
CEPH_NOSUB="/etc/apt/sources.list.d/ceph-no-subscription.list"

if grep -q "pve-no-subscription" "$PVE_NOSUB" 2>/dev/null; then
    info "PVE no-subscription repository already present — skipping."
else
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
        > "$PVE_NOSUB"
    info "Added PVE no-subscription repository."
fi

if grep -q "ceph-quincy" "$CEPH_NOSUB" 2>/dev/null; then
    info "Ceph Quincy no-subscription repository already present — skipping."
else
    echo "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription" \
        > "$CEPH_NOSUB"
    info "Added Ceph Quincy no-subscription repository."
fi

# =============================================================================
# STEP 4 — System Update
# =============================================================================
section "Step 4: Running System Update"

info "Updating package lists..."
apt-get update -qq

info "Upgrading packages (this may take a few minutes)..."
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"

info "System update complete."

# =============================================================================
# STEP 5 — Suppress Subscription Popup
# =============================================================================
section "Step 5: Suppressing Subscription Popup"

suppress_popup() {
    local JS_FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

    if [[ ! -f "$JS_FILE" ]]; then
        warn "proxmoxlib.js not found — skipping popup suppression."
        return
    fi

    if grep -q "cornet_patched" "$JS_FILE"; then
        info "Popup suppression already applied — skipping."
        return
    fi

    cp "$JS_FILE" "${JS_FILE}.bak"

    sed -i "s|res.data.status.toLowerCase() !== 'active'|res.data.status.toLowerCase() !== 'active' \&\& false /* cornet_patched */|g" "$JS_FILE"

    if grep -q "cornet_patched" "$JS_FILE"; then
        info "Subscription popup suppressed successfully."
    else
        warn "Patch did not apply. Check $JS_FILE manually."
        cp "${JS_FILE}.bak" "$JS_FILE"
    fi
}

suppress_popup

# =============================================================================
# STEP 6 — Install Helper Script + dpkg Hook for Popup Fix Persistence
# =============================================================================
section "Step 6: Installing dpkg Hook for Popup Fix Persistence"

HELPER_SCRIPT="/usr/local/bin/cornet-popup-fix"
HOOK_FILE="/etc/apt/apt.conf.d/99cornet-popup-fix"

cat > "$HELPER_SCRIPT" << 'EOF'
#!/bin/bash
JS="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
if [ -f "$JS" ] && ! grep -q "cornet_patched" "$JS"; then
    sed -i "s|res.data.status.toLowerCase() !== 'active'|res.data.status.toLowerCase() !== 'active' \&\& false /* cornet_patched */|g" "$JS"
fi
EOF

chmod +x "$HELPER_SCRIPT"
info "Helper script installed at $HELPER_SCRIPT."

cat > "$HOOK_FILE" << 'EOF'
DPkg::Post-Invoke { "/usr/local/bin/cornet-popup-fix"; };
EOF

info "dpkg hook installed at $HOOK_FILE."
info "Popup fix will be automatically reapplied after Proxmox updates."

# =============================================================================
# STEP 7 — Install CORNET MOTD
# =============================================================================
section "Step 7: Installing CORNET MOTD"

MOTD_DEST="/etc/update-motd.d/99-cornet-motd"
MOTD_URL="https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/cornet-motd.sh"

if curl -sf "$MOTD_URL" -o "$MOTD_DEST"; then
    chmod +x "$MOTD_DEST"
    info "CORNET MOTD installed at $MOTD_DEST."
else
    warn "Failed to download MOTD script from $MOTD_URL — skipping."
fi

# =============================================================================
# STEP 8 — Verify apt is Clean
# =============================================================================
section "Step 8: Verifying apt Configuration"

APT_ERRORS=$(apt-get update 2>&1 | grep -E "^E:|^W:" || true)

if [[ -z "$APT_ERRORS" ]]; then
    info "apt configuration is clean — no errors or warnings."
else
    warn "apt reported the following issues:"
    echo "$APT_ERRORS"
fi

# =============================================================================
# DONE
# =============================================================================
section "Setup Complete"

info "Node setup finished successfully."
info "Restarting pveproxy to apply the popup fix..."
systemctl restart pveproxy
info "Done. Refresh your browser and verify the subscription popup is gone."
info "The CORNET MOTD will appear on your next login."
