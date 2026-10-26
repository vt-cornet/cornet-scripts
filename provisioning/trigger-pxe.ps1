# ==============================================================================
# File: provisioning/trigger-pxe.ps1
# Purpose: Arm One-Time UEFI PXE Boot & Trigger Reboot on Dell Workstations
# ==============================================================================
# Target: Windows partition on Dell Pro Max Tower T2
# Run as: Administrator in PowerShell
#
# Pre-requisite checklist before executing:
#   1. Serva is running as Administrator on wvt465-xeon (128.173.94.81).
#   2. Serva MAC filter is configured with this machine's MAC address.
#   3. Autoinstall seed (/srv/autoinstall/<machine>/user-data) is live on LXC 210.
#   4. Status logger (port 5001) is active on LXC 210.
# ==============================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Dell Pro Max T2: One-Time UEFI Network Boot Trigger" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Locate Dell CCTK
$cctkPaths = @(
    "C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe",
    "C:\Program Files\Dell\Command Configure\X86_64\cctk.exe"
)
$cctk = $cctkPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($cctk) {
    Write-Host "[+] Using Dell Command | Configure: $cctk" -ForegroundColor Green
    
    # Check UEFI Network Stack is enabled
    $nwStack = & $cctk --UefiNwStack
    Write-Host "    UefiNwStack: $nwStack"

    # Arm one-time PXE next boot
    Write-Host "[+] Setting ForcePxeNextBoot=Enabled..." -ForegroundColor Yellow
    & $cctk --ForcePxeNextBoot=Enabled

    # Verify flag
    $status = & $cctk --ForcePxeNextBoot
    if ($status -match "Enabled") {
        Write-Host "    [OK] Next boot is successfully armed for UEFI Network Boot." -ForegroundColor Green
    } else {
        Write-Error "Failed to arm ForcePxeNextBoot. Output: $status"
        exit 1
    }
} else {
    Write-Host "[!] Dell CCTK not found. Falling back to native Windows bcdedit..." -ForegroundColor Yellow
    $bcd = bcdedit /enum firmware
    $guidLine = $bcd | Select-String -Pattern '\{[a-f0-9-]+\}' -Context 0, 3 | Where-Object { $_.Context.PostContext -match "Onboard NIC \(IPv4\)|UEFI HTTP/IPv4|Network" } | Select-Object -First 1

    if ($guidLine -and $guidLine.Line -match '(\{[a-f0-9-]+\})') {
        $netGuid = $matches[1]
        Write-Host "    [OK] Found UEFI Network Boot GUID: $netGuid" -ForegroundColor Green
        bcdedit /set "{fwbootmgr}" bootsequence $netGuid
    } else {
        Write-Error "Unable to auto-detect UEFI Network Boot GUID. Please install Dell Command | Configure."
        exit 1
    }
}

Write-Host ""
$confirm = Read-Host "Type 'yes' to reboot immediately into PXE network install"
if ($confirm -eq 'yes') {
    Write-Host "[+] Initiating immediate reboot..." -ForegroundColor Cyan
    shutdown /r /t 0
} else {
    Write-Host "Reboot canceled. The machine is armed and will PXE-boot on its next restart." -ForegroundColor Yellow
}
