# =============================================================================
# CORNET Windows Workstation Firewall Setup Script (PowerShell)
# =============================================================================
# Configures Windows Defender Advanced Firewall rules on Windows 10/11
# lab workstations (e.g. wvt465-xeon, wvt-pratheek-pc-win, wvt-wstation1-win).
#
# Enforces the exact same security policies as setup-workstation-firewall.sh:
#   - Default: BLOCK incoming, ALLOW outgoing on Domain, Private, and Public profiles
#   - Allow Remote Desktop (RDP - TCP/UDP 3389) ONLY from approved campus/VPN subnets
#   - Allow OpenSSH Server (SSH - TCP 22) ONLY from approved campus/VPN subnets
#   - Allow ICMPv4 (Ping) from approved subnets for monitoring and health checks
#   - Allow all Tailscale VPN traffic (100.64.0.0/10)
#   - Allow private SDR subnet traffic (192.168.0.0/16) for USRPs and smart plugs
#
# Usage (Run as Administrator):
#   powershell -ExecutionPolicy Bypass -File .\setup-windows-firewall.ps1
#
# Or direct one-line run:
#   irm https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/firewall/setup-windows-firewall.ps1 | iex
# =============================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " CORNET Workstation Firewall Setup (Windows Defender)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Administrator Privilege Verification
# -----------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be executed in an elevated PowerShell session (Run as Administrator)."
    exit 1
}

# -----------------------------------------------------------------------------
# 2. Approved Subnets (Identical to Proxmox cluster.fw IPSET)
# -----------------------------------------------------------------------------
$ApprovedSubnets = @(
    "128.173.52.0/24",         # Lab / Department Subnet
    "128.173.88.0/21",         # Campus Node Subnet
    "172.27.0.0/16",           # Internal Lab Subnet
    "172.29.0.0/16",           # Internal Lab Subnet
    "172.30.0.0/16",           # Internal Lab Subnet
    "198.82.18.128/26",        # CORNET Cluster Subnet
    "198.82.8.0/21",           # Virginia Tech Campus VPN Subnet
    "45.3.120.0/22",           # Approved External / VPN Range
    "45.3.124.0/23",           # Approved External / VPN Range
    "45.3.126.0/23"            # Approved External / VPN Range
)

# -----------------------------------------------------------------------------
# 3. Configure Default Firewall Profiles
# -----------------------------------------------------------------------------
Write-Host "[+] Step 1: Setting default firewall actions (Block Inbound, Allow Outbound)..." -ForegroundColor Yellow
Set-NetFirewallProfile -Profile Domain,Public,Private `
    -Enabled True `
    -DefaultInboundAction Block `
    -DefaultOutboundAction Allow `
    -NotifyOnListen False

Write-Host "    [✓] Inbound blocked, Outbound allowed across Domain, Private, and Public profiles." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. Remove / Disable Generic Wide-Open Windows Rules
# -----------------------------------------------------------------------------
Write-Host "[+] Step 2: Suppressing generic wide-open RDP and SSH rules..." -ForegroundColor Yellow

# Disable built-in wide-open Remote Desktop rules
Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | `
    Where-Object { $_.Direction -eq "Inbound" } | `
    Disable-NetFirewallRule -ErrorAction SilentlyContinue

# Disable generic OpenSSH server rule if created by Windows feature installer
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | `
    Disable-NetFirewallRule -ErrorAction SilentlyContinue

# Remove any existing CORNET rules to ensure clean idempotency
Get-NetFirewallRule -Name "CORNET-*" -ErrorAction SilentlyContinue | `
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

Write-Host "    [✓] Built-in wide-open rules suppressed." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. Create Subnet-Restricted Inbound Rules
# -----------------------------------------------------------------------------
Write-Host "[+] Step 3: Installing CORNET approved-subnet firewall rules..." -ForegroundColor Yellow

# 5.1 Remote Desktop (TCP 3389)
New-NetFirewallRule -Name "CORNET-RDP-In-TCP" `
    -DisplayName "CORNET - Remote Desktop (TCP 3389 - Approved Subnets)" `
    -Description "Allows inbound RDP connections only from approved Virginia Tech and CORNET subnets." `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 3389 `
    -Action Allow `
    -RemoteAddress $ApprovedSubnets `
    -Profile Any `
    -Enabled True | Out-Null
Write-Host "    [✓] Allowed RDP (TCP 3389) from 10 approved subnets." -ForegroundColor Green

# 5.2 Remote Desktop (UDP 3389 - RDP 8.0+ acceleration)
New-NetFirewallRule -Name "CORNET-RDP-In-UDP" `
    -DisplayName "CORNET - Remote Desktop UDP (UDP 3389 - Approved Subnets)" `
    -Description "Allows inbound RDP UDP stream acceleration only from approved subnets." `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 3389 `
    -Action Allow `
    -RemoteAddress $ApprovedSubnets `
    -Profile Any `
    -Enabled True | Out-Null
Write-Host "    [✓] Allowed RDP (UDP 3389) from 10 approved subnets." -ForegroundColor Green

# 5.3 OpenSSH Server (TCP 22)
New-NetFirewallRule -Name "CORNET-SSH-In-TCP" `
    -DisplayName "CORNET - OpenSSH Server (TCP 22 - Approved Subnets)" `
    -Description "Allows inbound SSH connections only from approved Virginia Tech and CORNET subnets." `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -Action Allow `
    -RemoteAddress $ApprovedSubnets `
    -Profile Any `
    -Enabled True | Out-Null
Write-Host "    [✓] Allowed SSH (TCP 22) from 10 approved subnets." -ForegroundColor Green

# 5.4 ICMPv4 (Ping / Echo Request)
New-NetFirewallRule -Name "CORNET-ICMP-In" `
    -DisplayName "CORNET - ICMPv4 Ping (Echo Request - Approved Subnets)" `
    -Description "Allows ICMPv4 ping requests from approved subnets for health and reachability checks." `
    -Direction Inbound `
    -Protocol ICMPv4 `
    -IcmpType 8 `
    -Action Allow `
    -RemoteAddress $ApprovedSubnets `
    -Profile Any `
    -Enabled True | Out-Null
Write-Host "    [✓] Allowed ICMP Ping from 10 approved subnets." -ForegroundColor Green

# 5.5 Tailscale VPN Access
New-NetFirewallRule -Name "CORNET-Tailscale-In" `
    -DisplayName "CORNET - Tailscale VPN Carrier Grade NAT" `
    -Description "Allows all inbound traffic arriving from the Tailscale overlay network." `
    -Direction Inbound `
    -Action Allow `
    -RemoteAddress "100.64.0.0/10" `
    -Profile Any `
    -Enabled True | Out-Null
Write-Host "    [✓] Allowed Tailscale overlay network (100.64.0.0/10)." -ForegroundColor Green

# 5.6 USRP SDR & Smart Plug Management LAN
New-NetFirewallRule -Name "CORNET-SDR-Private-In" `
    -DisplayName "CORNET - SDR & Smart Plug Private LAN" `
    -Description "Allows inbound traffic from USRP SDRs (192.168.10.x, 192.168.20.x, 192.168.40.x) and smart plugs (192.168.8.x)." `
    -Direction Inbound `
    -Action Allow `
    -RemoteAddress "192.168.0.0/16" `
    -Profile Any `
    -Enabled True | Out-Null
Write-Host "    [✓] Allowed private SDR and smart plug traffic (192.168.0.0/16)." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 6. Verification
# -----------------------------------------------------------------------------
Write-Host "`n=== Active CORNET Firewall Rules ===" -ForegroundColor Cyan
Get-NetFirewallRule -Name "CORNET-*" | `
    Format-Table Name, DisplayName, Enabled, Direction, Action -AutoSize

Write-Host "[✓] Windows Defender Firewall successfully hardened for CORNET." -ForegroundColor Green
Write-Host "    Remote Desktop and SSH are now strictly restricted to campus and VPN subnets.`n" -ForegroundColor Green
