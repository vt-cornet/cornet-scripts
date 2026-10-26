# ==============================================================================
# File: provisioning/switch-ahci.ps1
# Purpose: Pre-Stage AHCI Drivers & Switch Dell T2 BIOS Storage Mode to AHCI
# ==============================================================================
# Target: Dell Pro Max Tower T2 Workstations (wvt-wstation1, wstation2, pratheek-pc)
# Run as: Administrator in PowerShell on the target machine
#
# Why this is required:
#   Dell factory BIOS ships with EmbSataRaid=Raid (Intel VMD enabled).
#   Under Raid/VMD, the Linux live kernel sees 0 NVMe disks ('Unknown Bus Offset 3').
#   Switching directly to AHCI in BIOS causes Windows to crash with INACCESSIBLE_BOOT_DEVICE.
#   Pre-staging storahci, iaStorV, and iaStorAVC in the Windows registry ensures
#   Windows boots successfully under AHCI without bricking the OS.
#
# Safety Precaution:
#   Have someone physically present on site with a monitor. If the machine halts at
#   recovery, boot into Safe Mode with Command Prompt, then reboot normally.
# ==============================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Dell Pro Max T2: AHCI Driver Pre-Stage & Mode Switch" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check BitLocker Status
Write-Host "[1/4] Checking BitLocker status on C:..." -ForegroundColor Yellow
$bitlocker = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
if ($bitlocker -and $bitlocker.ProtectionStatus -eq "On") {
    Write-Warning "BitLocker is ENABLED on drive C:."
    Write-Warning "You MUST suspend BitLocker before switching storage mode to prevent recovery lockouts:"
    Write-Warning "  manage-bde -protectors -disable C: -RebootCount 2"
    $confirm = Read-Host "Type 'yes' if you have backed up your recovery key and suspended BitLocker"
    if ($confirm -ne 'yes') {
        Write-Error "Operation aborted by user."
        exit 1
    }
} else {
    Write-Host "  [OK] BitLocker is disabled / off." -ForegroundColor Green
}

# 2. Disable Fast Startup (Hybrid Boot)
# Crucial for dual-boot disk integrity, firmware state, and Wake-on-LAN
Write-Host "[2/5] Disabling Windows Fast Startup..." -ForegroundColor Yellow
$powerReg = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
if (Test-Path $powerReg) {
    Set-ItemProperty -Path $powerReg -Name "HiberbootEnabled" -Value 0
    Write-Host "  [OK] Disabled Fast Startup (HiberbootEnabled=0)" -ForegroundColor Green
}

# 3. Pre-stage AHCI and Storage Drivers
Write-Host "[3/5] Pre-staging AHCI drivers in Windows registry..." -ForegroundColor Yellow
$services = @('iaStorV', 'iaStorAVC', 'storahci')
foreach ($svc in $services) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name "Start" -Value 0
        New-Item -Path "$path\StartOverride" -Force | Out-Null
        Set-ItemProperty -Path "$path\StartOverride" -Name "0" -Value 0 -Type DWord
        Write-Host "  [OK] Configured $svc (Start=0, StartOverride=0)" -ForegroundColor Green
    }
}

# 4. Locate Dell Command | Configure (cctk.exe)
Write-Host "[4/5] Checking Dell CCTK executable..." -ForegroundColor Yellow
$cctkPaths = @(
    "C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe",
    "C:\Program Files\Dell\Command Configure\X86_64\cctk.exe"
)
$cctk = $cctkPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $cctk) {
    Write-Error "Dell Command | Configure (cctk.exe) not found. Please install Dell Command Configure."
    exit 1
}
Write-Host "  [OK] Found cctk: $cctk" -ForegroundColor Green

# 5. Check & Switch BIOS Storage Mode
Write-Host "[5/5] Configuring BIOS Storage Mode..." -ForegroundColor Yellow
$currentMode = & $cctk --EmbSataRaid
Write-Host "  Current Mode: $currentMode"

if ($currentMode -match "Ahci") {
    Write-Host "  [OK] System is already set to AHCI. No BIOS change required." -ForegroundColor Green
} else {
    Write-Host "  Switching EmbSataRaid to Ahci..."
    & $cctk --EmbSataRaid=Ahci
    $newMode = & $cctk --EmbSataRaid
    Write-Host "  Updated Mode: $newMode" -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Pre-staging complete. You must reboot Windows now:" -ForegroundColor Cyan
Write-Host "   shutdown /r /t 0" -ForegroundColor Yellow
Write-Host ""
Write-Host " If Windows encounters INACCESSIBLE_BOOT_DEVICE on first reboot:" -ForegroundColor Yellow
Write-Host "   1. Select Advanced Options -> Safe Mode with Command Prompt"
Write-Host "   2. Run: shutdown /r /t 0"
Write-Host "   3. Windows will boot normally on the second attempt."
Write-Host "==========================================================" -ForegroundColor Cyan
