#!/usr/bin/env bash
# ==============================================================================
# File: remote-desktop/fix-gnome-rdp.sh
# Purpose: Rollback FreeRDP/WinPR Libraries to Resolve macOS Windows App Handshake
# ==============================================================================
# Upstream Ubuntu updates to FreeRDP 3.32+ introduce a TLS handshake regression
# with the macOS Microsoft Remote Desktop / Windows App client.
#
# This script:
#   1. Clears prior apt package holds.
#   2. Rolls back libfreerdp3 and libwinpr3 to known working releases:
#      - Ubuntu 24.04: 3.31.0+dfsg-0ubuntu0.24.04.1 (via official Ubuntu snapshot archive)
#      - Ubuntu 26.04: 3.24.2+dfsg-1ubuntu1 (via apt --allow-downgrades)
#   3. Pins the working library packages (apt-mark hold) to prevent regression.
#   4. Purges incompatible winpr-utils tools.
#   5. Regenerates TLS certificates and restarts the GNOME Remote Desktop service.
#
# Usage:
#   sudo ./fix-gnome-rdp.sh
#
# Or direct one-line run:
#   curl -sSL https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/remote-desktop/fix-gnome-rdp.sh | sudo bash
# ==============================================================================

set -euo pipefail

# --- Root Check --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root (use sudo)." >&2
   exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# --- Detect Ubuntu Version ---------------------------------------------------
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    UBUNTU_VER="${VERSION_ID:-}"
else
    echo "[ERROR] /etc/os-release not found. Cannot determine Ubuntu version." >&2
    exit 1
fi

echo "=========================================================="
echo " CORNET GNOME Remote Desktop (RDP) Fix & FreeRDP Rollback"
echo " Detected Ubuntu Version: ${UBUNTU_VER} (${VERSION_CODENAME:-unknown})"
echo "=========================================================="

# Ensure wget and openssl are available
command -v wget >/dev/null 2>&1 || apt-get update -qq && apt-get install -y -qq wget openssl

# --- Step 1: Unhold Existing Packages ----------------------------------------
echo "[1/5] Clearing prior apt holds..."
apt-mark unhold libfreerdp-client3-3 libfreerdp-server3-3 libfreerdp3-3 libwinpr3-3 libwinpr-tools3-3 2>/dev/null || true

# --- Step 2: Version-Specific Rollback ---------------------------------------
echo "[2/5] Performing target version rollback..."
if [[ "${UBUNTU_VER}" == "24.04" ]]; then
    TARGET_VER="3.31.0+dfsg-0ubuntu0.24.04.1"
    echo "Configuring rollback for Ubuntu 24.04 (Target: ${TARGET_VER})..."

    TMP_DIR=$(mktemp -d /tmp/freerdp-rollback-XXXXXX)
    trap 'rm -rf "${TMP_DIR}"' EXIT
    cd "${TMP_DIR}"

    # Official Canonical snapshot archive for noble (immutable and guaranteed available)
    SNAP="https://snapshot.ubuntu.com/ubuntu/20260915T000000Z/pool/main/f/freerdp3"
    echo "Downloading verified 3.31.0 deb archives from Ubuntu snapshot archive..."
    if ! wget -q -c \
        "${SNAP}/libwinpr3-3_${TARGET_VER}_amd64.deb" \
        "${SNAP}/libfreerdp3-3_${TARGET_VER}_amd64.deb" \
        "${SNAP}/libfreerdp-server3-3_${TARGET_VER}_amd64.deb" \
        "${SNAP}/libfreerdp-client3-3_${TARGET_VER}_amd64.deb"; then
        
        # Fallback to launchpad librarian pool if snapshot is unreachable
        echo "[!] Snapshot mirror unreachable; trying Launchpad archive..."
        rm -f ./*.deb
        BASE_URL="http://launchpadlibrarian.net"
        wget -q -c \
            "${BASE_URL}/745585090/libwinpr3-3_${TARGET_VER}_amd64.deb" \
            "${BASE_URL}/745585091/libfreerdp3-3_${TARGET_VER}_amd64.deb" \
            "${BASE_URL}/745585093/libfreerdp-server3-3_${TARGET_VER}_amd64.deb" \
            "${BASE_URL}/745585089/libfreerdp-client3-3_${TARGET_VER}_amd64.deb"
    fi

    echo "Installing rollback deb packages..."
    dpkg -i ./*.deb || apt-get install -f -y
    cd / && rm -rf "${TMP_DIR}"
    trap - EXIT

elif [[ "${UBUNTU_VER}" == "26.04" ]]; then
    TARGET_VER="3.24.2+dfsg-1ubuntu1"
    echo "Configuring rollback for Ubuntu 26.04 (Target: ${TARGET_VER})..."

    apt-get update -qq
    apt-get install --allow-downgrades -y -qq \
        libfreerdp-client3-3="${TARGET_VER}" \
        libfreerdp-server3-3="${TARGET_VER}" \
        libfreerdp3-3="${TARGET_VER}" \
        libwinpr3-3="${TARGET_VER}"
else
    echo "[ERROR] Unsupported Ubuntu release: ${UBUNTU_VER}. Supported: 24.04, 26.04." >&2
    exit 1
fi

# --- Step 3: Pin Core Libraries ----------------------------------------------
echo "[3/5] Pinning packages to prevent automatic upgrades..."
apt-mark hold libfreerdp-client3-3 libfreerdp-server3-3 libfreerdp3-3 libwinpr3-3

# --- Step 4: Purge Mismatched Tools ------------------------------------------
echo "[4/5] Purging mismatched winpr tools and stale configs..."
apt-get remove -y -qq winpr-utils libwinpr-tools3-3 2>/dev/null || true
dpkg -P winpr-utils libwinpr-tools3-3 2>/dev/null || true

# --- Step 5: Regenerate TLS Certificates & Restart ---------------------------
echo "[5/5] Regenerating RDP TLS certificates and restarting service..."

# Stop any dangling daemon processes
pkill -f gnome-remote-desktop 2>/dev/null || true

# 1. System daemon (/etc/gnome-remote-desktop)
if systemctl is-active --quiet gnome-remote-desktop 2>/dev/null || systemctl is-enabled --quiet gnome-remote-desktop 2>/dev/null; then
    echo "Updating system-level service configuration..."
    mkdir -p /etc/gnome-remote-desktop
    openssl req -new -x509 -days 730 -nodes \
        -out /etc/gnome-remote-desktop/rdp-tls.crt \
        -keyout /etc/gnome-remote-desktop/rdp-tls.key \
        -subj "/CN=$(hostname)" 2>/dev/null

    chmod 600 /etc/gnome-remote-desktop/rdp-tls.key
    chmod 644 /etc/gnome-remote-desktop/rdp-tls.crt
    chown -R gnome-remote-desktop:gnome-remote-desktop /etc/gnome-remote-desktop/ 2>/dev/null || true

    grdctl --system rdp set-tls-cert /etc/gnome-remote-desktop/rdp-tls.crt 2>/dev/null || true
    grdctl --system rdp set-tls-key /etc/gnome-remote-desktop/rdp-tls.key 2>/dev/null || true
    systemctl restart gnome-remote-desktop
fi

# 2. User sessions (for non-system mode daemon setups)
TARGET_USER="${SUDO_USER:-}"
if [[ -n "${TARGET_USER}" && "${TARGET_USER}" != "root" ]]; then
    USER_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
    USER_UID=$(id -u "${TARGET_USER}")
    USER_GRD_DIR="${USER_HOME}/.local/share/gnome-remote-desktop"

    mkdir -p "${USER_GRD_DIR}"
    openssl req -new -x509 -days 730 -nodes \
        -out "${USER_GRD_DIR}/rdp-tls.crt" \
        -keyout "${USER_GRD_DIR}/rdp-tls.key" \
        -subj "/CN=$(hostname)" 2>/dev/null

    chmod 600 "${USER_GRD_DIR}/rdp-tls.key"
    chmod 644 "${USER_GRD_DIR}/rdp-tls.crt"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.local/share" 2>/dev/null || true

    # Bind in user session if user systemd dbus instance is active
    export XDG_RUNTIME_DIR="/run/user/${USER_UID}"
    if [[ -d "${XDG_RUNTIME_DIR}" ]]; then
        sudo -u "${TARGET_USER}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
            grdctl rdp set-tls-cert "${USER_GRD_DIR}/rdp-tls.crt" 2>/dev/null || true
        sudo -u "${TARGET_USER}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
            grdctl rdp set-tls-key "${USER_GRD_DIR}/rdp-tls.key" 2>/dev/null || true
        sudo -u "${TARGET_USER}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
            systemctl --user restart gnome-remote-desktop 2>/dev/null || true
    fi
fi

echo ""
echo "=========================================================="
echo " Rollback completed successfully!"
echo " Current installed FreeRDP/WinPR packages:"
dpkg-query -W 'libfreerdp*' 'libwinpr*'
echo ""
echo " Active holds:"
apt-mark showhold
echo "=========================================================="
