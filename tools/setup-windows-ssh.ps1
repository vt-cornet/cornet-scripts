# =============================================================================
# CORNET Windows Workstation OpenSSH Setup Script (PowerShell)
# =============================================================================
# Enables OpenSSH Server on Windows 10/11 workstations (e.g. wvt-pratheek-pc,
# wvt-wstation1, wvt465-xeon), configures automatic service startup, authorizes
# the lab ED25519 SSH public key, and configures strict NTFS permissions.
#
# Usage (Run as Administrator in PowerShell):
#   powershell -ExecutionPolicy Bypass -File .\setup-windows-ssh.ps1
#
# Or direct one-liner from Windows PowerShell:
#   irm https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/tools/setup-windows-ssh.ps1 | iex
# =============================================================================

#Requires -RunAsAdministrator

if (-not $PublicKey) {
    $PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMNVMN2kfORvPG75AQnjSl61N8dX1eNYx4EtZHfZGBxY pratheek@cornet"
}

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " CORNET Windows OpenSSH Server Setup" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Administrator Check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be executed in an elevated PowerShell session (Run as Administrator)."
    exit 1
}

# 2. Install OpenSSH Server Capability
Write-Host "[1/5] Checking OpenSSH Server capability..." -ForegroundColor Yellow
$sshCapability = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" } | Select-Object -First 1

if (-not $sshCapability) {
    Write-Error "OpenSSH.Server capability was not found in Windows image."
    exit 1
}

if ($sshCapability.State -ne "Installed") {
    Write-Host "  Installing OpenSSH Server feature..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name $sshCapability.Name | Out-Null
    Write-Host "  [OK] OpenSSH Server installed." -ForegroundColor Green
} else {
    Write-Host "  [OK] OpenSSH Server is already installed." -ForegroundColor Green
}

# 3. Configure and Start sshd Service
Write-Host "[2/5] Configuring sshd service..." -ForegroundColor Yellow
Set-Service -Name sshd -StartupType 'Automatic'
if ((Get-Service -Name sshd).Status -ne 'Running') {
    Start-Service sshd
    Write-Host "  [OK] sshd service started." -ForegroundColor Green
} else {
    Write-Host "  [OK] sshd service is already running." -ForegroundColor Green
}

# 4. Authorize SSH Public Key
Write-Host "[3/5] Authorizing SSH public key..." -ForegroundColor Yellow

# Ensure C:\ProgramData\ssh exists
$sshDir = "$env:ProgramData\ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

# In Windows OpenSSH, administrative users authenticate via administrators_authorized_keys
$adminKeysPath = "$sshDir\administrators_authorized_keys"
if (Test-Path $adminKeysPath) {
    $existing = Get-Content $adminKeysPath -Raw -ErrorAction SilentlyContinue
    if ($existing -notmatch [regex]::Escape($PublicKey.Trim())) {
        Add-Content -Path $adminKeysPath -Value "`n$PublicKey" -Encoding Ascii
        Write-Host "  [OK] Appended key to $adminKeysPath" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Key already present in $adminKeysPath" -ForegroundColor Green
    }
} else {
    Set-Content -Path $adminKeysPath -Value $PublicKey -Encoding Ascii
    Write-Host "  [OK] Created $adminKeysPath" -ForegroundColor Green
}

# Also populate current user's profile ~/.ssh/authorized_keys
$userSshDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $userSshDir)) {
    New-Item -ItemType Directory -Path $userSshDir -Force | Out-Null
}
$userKeysPath = "$userSshDir\authorized_keys"
if (Test-Path $userKeysPath) {
    $existingUser = Get-Content $userKeysPath -Raw -ErrorAction SilentlyContinue
    if ($existingUser -notmatch [regex]::Escape($PublicKey.Trim())) {
        Add-Content -Path $userKeysPath -Value "`n$PublicKey" -Encoding Ascii
        Write-Host "  [OK] Appended key to $userKeysPath" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Key already present in $userKeysPath" -ForegroundColor Green
    }
} else {
    Set-Content -Path $userKeysPath -Value $PublicKey -Encoding Ascii
    Write-Host "  [OK] Created $userKeysPath" -ForegroundColor Green
}

# 5. Set Strict NTFS ACL Permissions (Required by OpenSSH)
Write-Host "[4/5] Applying strict ACL permissions (disabling inheritance)..." -ForegroundColor Yellow

# Windows OpenSSH rejects administrators_authorized_keys if anyone other than SYSTEM or Administrators has access
& icacls.exe $adminKeysPath /inheritance:r /grant "NT AUTHORITY\SYSTEM:(F)" "BUILTIN\Administrators:(F)" | Out-Null
Write-Host "  [OK] Secured $adminKeysPath" -ForegroundColor Green

# Secure user authorized_keys
& icacls.exe $userKeysPath /inheritance:r /grant "NT AUTHORITY\SYSTEM:(F)" "$($env:USERNAME):(F)" "BUILTIN\Administrators:(F)" | Out-Null
Write-Host "  [OK] Secured $userKeysPath" -ForegroundColor Green

# 6. Configure Windows Defender Firewall Rule for Port 22
Write-Host "[5/5] Ensuring firewall allows port 22..." -ForegroundColor Yellow
$fwRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
        -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 | Out-Null
    Write-Host "  [OK] Created firewall rule for port 22." -ForegroundColor Green
} else {
    Write-Host "  [OK] Firewall rule for OpenSSH is active." -ForegroundColor Green
}

# Restart sshd to ensure permissions and configuration are refreshed
Restart-Service sshd

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " OpenSSH setup completed successfully!" -ForegroundColor Green
Write-Host " Test access from another machine with:" -ForegroundColor Cyan
Write-Host "   ssh -i ~/.ssh/id_ed25519 $($env:USERNAME)@$( (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match 'Ethernet' -and $_.IPAddress -notlike '169.*' }).IPAddress )" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green
