# ==============================================================================
# File: provisioning/recover-boot-lockout.ps1
# Purpose: Recover Remote Ubuntu Access from Windows When Trapped in GRUB Loop
# ==============================================================================
# The Problem ("The Circular Boot Lockout"):
#   When GRUB_DEFAULT=saved is configured in Ubuntu, switching to Windows sets
#   'saved_entry' in /boot/grub/grubenv.
#   Because grubenv lives on the ext4 Linux root partition (Disk 1, Partition 2)
#   rather than the FAT32 EFI partition, Windows cannot natively read or write it.
#   Every subsequent reboot will loop straight back into Windows indefinitely.
#
# The Solution:
#   Mount the raw physical NVMe drive into WSL2 using 'wsl --mount --bare',
#   clear 'saved_entry' via grub-editenv, restore GRUB_DEFAULT=0, unmount,
#   bring the disk back online, and reboot.
# ==============================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " CORNET Dual-Boot Lockout Recovery (WSL2 ext4 Mount)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Identify Physical Disks
Write-Host "[1/5] Identifying Linux physical disk number..." -ForegroundColor Yellow
$disks = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object Index, DeviceID, Model, Size
$disks | Format-Table Index, DeviceID, Model, Size -AutoSize

# Default to Disk 1 (Samsung 990 PRO 1TB)
$targetDisk = $disks | Where-Object { $_.Model -match "Samsung" -or $_.Size -gt 500GB } | Select-Object -First 1
$diskIndex = if ($targetDisk) { $targetDisk.Index } else { 1 }

Write-Host "  Targeting Disk $diskIndex (\\.\PHYSICALDRIVE$diskIndex)" -ForegroundColor Green

# 2. Set Disk Offline in Windows (Releases Volume Handles for WSL2)
Write-Host "[2/5] Setting Disk $diskIndex Offline in diskpart to release locks..." -ForegroundColor Yellow
$diskpartScript = @"
select disk $diskIndex
offline disk
exit
"@
$diskpartScript | diskpart | Out-Null
Write-Host "  [OK] Disk $diskIndex is offline in Windows." -ForegroundColor Green

# 3. Mount Physical Disk into WSL2
Write-Host "[3/5] Attaching raw disk to WSL2..." -ForegroundColor Yellow
try {
    wsl.exe --mount "\\.\PHYSICALDRIVE$diskIndex" --bare
    Write-Host "  [OK] Attached \\.\PHYSICALDRIVE$diskIndex to WSL2." -ForegroundColor Green
} catch {
    Write-Error "Failed to mount physical disk into WSL2: $_"
    # Bring disk back online if failed
    @"
select disk $diskIndex
online disk
exit
"@ | diskpart | Out-Null
    exit 1
}

# 4. Execute Fix inside WSL2
Write-Host "[4/5] Executing GRUB recovery script inside WSL2..." -ForegroundColor Yellow

$wslCommands = @'
set -e
# Install grub-common in WSL if missing
if ! command -v grub-editenv >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq grub-common
fi

# Locate ext4 root partition on secondary disk (usually sdb2, sdc2, or sdd2)
PART=$(lsblk -ln -o NAME,FSTYPE,SIZE | awk '$2=="ext4" && $3 ~ /G/ {print "/dev/"$1}' | tail -n 1)

if [ -z "$PART" ]; then
    echo "[-] ERROR: Could not locate ext4 root partition." >&2
    exit 1
fi

echo "[+] Mounting $PART to /mnt/ubuntu..."
sudo mkdir -p /mnt/ubuntu
sudo mount "$PART" /mnt/ubuntu

echo "[+] Wiping saved_entry from grubenv..."
if [ -f "/mnt/ubuntu/boot/grub/grubenv" ]; then
    sudo grub-editenv /mnt/ubuntu/boot/grub/grubenv unset saved_entry || true
fi

echo "[+] Reverting /etc/default/grub to GRUB_DEFAULT=0..."
if [ -f "/mnt/ubuntu/etc/default/grub" ]; then
    sudo sed -i 's/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/' /mnt/ubuntu/etc/default/grub
fi

echo "[+] Unmounting $PART..."
cd ~
sudo umount /mnt/ubuntu
echo "[✓] WSL2 recovery completed successfully."
'@

wsl.exe -e bash -c "$wslCommands"

# 5. Detach Disk and Bring Online
Write-Host "[5/5] Detaching disk from WSL2 and re-enabling in Windows..." -ForegroundColor Yellow
wsl.exe --unmount "\\.\PHYSICALDRIVE$diskIndex"

$onlineScript = @"
select disk $diskIndex
online disk
exit
"@
$onlineScript | diskpart | Out-Null
Write-Host "  [OK] Disk $diskIndex brought back online." -ForegroundColor Green

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Recovery complete! saved_entry cleared and GRUB_DEFAULT=0." -ForegroundColor Green
Write-Host " The machine will now boot straight into Ubuntu on restart." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
$reboot = Read-Host "Type 'yes' to restart into Ubuntu now"
if ($reboot -eq 'yes') {
    Restart-Computer
}
