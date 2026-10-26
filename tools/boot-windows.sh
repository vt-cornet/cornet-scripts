#!/bin/bash
# =============================================================================
# CORNET Lab Workstation Dual-Boot Helper: boot-windows
# =============================================================================
# Location on workstation: /usr/local/bin/boot-windows
#
# Inspects the UEFI boot order using efibootmgr, finds the entry for
# "Windows Boot Manager", sets it as the next one-time boot target,
# and reboots the machine directly into Windows.
# =============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (or via sudo)." >&2
    exit 1
fi

WIN_BOOT=$(efibootmgr | grep -i "Windows Boot Manager" | sed -n 's/Boot\([0-9A-Fa-f]\{4\}\)\*.*/\1/p' | head -n1)

if [ -n "$WIN_BOOT" ]; then
    echo "Setting next boot to Windows (Boot$WIN_BOOT) and rebooting..."
    efibootmgr -n "$WIN_BOOT"
    reboot
else
    echo "Error: Windows Boot Manager entry not found in EFI boot manager." >&2
    exit 1
fi
