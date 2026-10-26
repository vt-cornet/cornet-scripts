# CORNET Bare-Metal Ubuntu Provisioning via PXE (Dell Pro Max T2)

Automated, unattended bare-metal UEFI PXE deployment architecture for CORNET lab workstations (**Dell Pro Max Tower T2 / FCT2250**) running dual-boot Windows 10/11 and Ubuntu.

Proven and verified on `wvt-wstation1-ubuntu`, `wvt-wstation2-ubuntu`, and `wvt-pratheek-pc-ubuntu`.

---

## 1. Architecture & Network Constraint

Because the Proxmox cluster nodes (`198.82.18.128/26`) and the lab workstations (`128.173.92.0/22`) sit on **different routed subnets**, Layer 2 DHCP broadcasts cannot cross the router to reach `cornet-node01` or LXC 210. 

Additionally, the Virginia Tech campus DHCP relay forwards only to the central campus DHCP server (`198.82.247.52`), causing ProxyDHCP implementations on LXC 210 to fail on real hardware.

```
+-----------------------------------------------------------------------------------------+
|                                    TARGET SUBNET (128.173.92.0/22)                      |
|                                                                                         |
|   +------------------------------------+          +----------------------------------+  |
|   |  Target Workstations (Dell T2)     |          |  Xeon-UB (wvt465-xeon)           |  |
|   |  - wvt-wstation1 (128.173.94.17)   |          |  - IP: 128.173.94.81/22          |  |
|   |  - wvt-wstation2 (128.173.94.34)   | <======> |  - Serva v5.0.0 (Admin)          |  |
|   |  - wvt-pratheek-pc (128.173.94.78) |   DHCP   |  - Local Full DHCP (size 1 pool) |  |
|   +-----------------+------------------+   TFTP   |  - Local TFTP: bootx64, grub.cfg |  |
|                     |                             +----------------------------------+  |
+---------------------|-------------------------------------------------------------------+
                      |
                      | Routed HTTP Requests (Default Gateway: 128.173.92.1)
                      v
+-----------------------------------------------------------------------------------------+
|                              PROXMOX CLUSTER SUBNET (198.82.18.128/26)                  |
|                                                                                         |
|   +------------------------------------+          +----------------------------------+  |
|   |  LXC 210 (pxe-server: 198.82.18.151) |          |  LXC 200 (dns-server: 18.150)    |  |
|   |  - Nginx (Port 80): autoinstall seed|          |  - DDNS API (Port 5000)          |  |
|   |  - status-api (Port 5001): Webhook |          |  - dnsmasq DNS Resolver          |  |
|   +------------------------------------+          +----------------------------------+  |
+-----------------------------------------------------------------------------------------+
```

### Flow of Execution
1. **DHCP & TFTP Handshake:** The target workstation broadcasts DHCP; **Serva** on `wvt465-xeon` (`128.173.94.81`) answers via strict MAC filtering with an IP pool of 1, handing over `bootx64.efi`, `grubx64.efi`, and `grub.cfg`.
2. **Kernel & ISO Download:** GRUB boots the signed Linux kernel and pulls the live Ubuntu ISO into a 6GB RAM disk directly from Canonical over the campus gateway (`128.173.92.1`).
3. **Autoinstall Seed:** The Subiquity installer pulls `user-data` and `meta-data` from **LXC 210** (`http://198.82.18.151/autoinstall/<machine>/`) over routed HTTP.
4. **Live Stage Telemetry:** Subiquity streams real-time stage transitions to the Flask logger on **LXC 210** (`http://198.82.18.151:5001/install-status/<machine>`).
5. **Reboot & DDNS Registration:** The system completes installation, reboots into Ubuntu, and registers its IP with **LXC 200** (`198.82.18.150:5000`).

---

## 2. Reference Values & Hardware Map

| Host / Target | Hardware Model | NIC / MAC Address | IP Address | Role |
| :--- | :--- | :--- | :--- | :--- |
| **`node01`** | Proxmox VE 8.4 | vmbr0 | `198.82.18.154/26` | Cluster host (GW: `198.82.18.129`) |
| **`LXC 200`** | Ubuntu Container | eth0 / veth | `198.82.18.150` | `dns-server` (dnsmasq, DDNS API :5000) |
| **`LXC 210`** | Ubuntu Container | eth0 / veth | `198.82.18.151` | `pxe-server` (nginx :80, status logger :5001) |
| **`wvt465-xeon`** | Dell Precision 7910 | `34:17:eb:de:5c:dd` | `128.173.94.81/22` | Local DHCP/TFTP relay via Serva |
| **`wvt-wstation1`**| Dell Pro Max T2 | `ac:b4:80:3a:3a:82` | `128.173.94.17/22` | Target: Micron 256G + Samsung 990 1T |
| **`wvt-wstation2`**| Dell Pro Max T2 | `e8:cf:83:27:66:81` | `128.173.94.34/22` | Target: Micron 256G + Samsung 990 1T |
| **`wvt-pratheek-pc`**| Dell Pro Max T2 | `ac:b4:80:3a:3a:9e` | `128.173.94.78/22` | Target: Micron 256G + Samsung 990 1T |
| **VT DNS Servers** | Upstream DNS | N/A | `198.82.247.66`, `198.82.247.98` | Resolvers passed to installer |

### Workstation Disk Layout
- **Disk 0 (Micron 256GB NVMe, GPT):** Windows 10/11 partitions (untouched).
- **Disk 1 (Samsung 990 PRO 1TB NVMe, RAW):** Target for Ubuntu. The autoinstall seed uses `size: largest` to select this drive automatically.

---

## 3. Storage Mode Switch (RAID to AHCI)

### The Intel VMD Issue
Dell factory BIOS ships with `EmbSataRaid=Raid` (Intel Volume Management Device / VMD enabled). Under RAID mode, the Linux kernel cannot detect the NVMe drives (`dmesg: vmd: Unknown Bus Offset Setting (3)`, `lsblk` displays only loop devices, and Subiquity fails with `Failed to find matching device`).

### The Pre-Staging Fix ([`switch-ahci.ps1`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/switch-ahci.ps1))
Switching the BIOS setting to AHCI while Windows is installed causes Windows to fail on next boot with `INACCESSIBLE_BOOT_DEVICE` unless the AHCI drivers are pre-staged in the registry:

1. **Pre-stage Registry in Windows (as Administrator):**
   ```powershell
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\storahci" -Name "Start" -Value 0
   New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\storahci\StartOverride" -Force | Out-Null
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\storahci\StartOverride" -Name "0" -Value 0 -Type DWord
   ```
2. **Switch BIOS SATA Controller via Dell CCTK:**
   ```powershell
   & "C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe" --EmbSataRaid=Ahci
   ```
3. **Reboot Windows:** `shutdown /r /t 0`.
4. **Safe Mode Recovery (if first boot encounters `INACCESSIBLE_BOOT_DEVICE`):**
   - Boot into **Safe Mode with Command Prompt**.
   - Check `Get-Service storahci` (Running).
   - Reboot via `shutdown /r /t 0`. Windows will boot normally on the second attempt.

---

## 4. Server-Side Setup

### A. Serva Configuration (`wvt465-xeon` / `128.173.94.81`)
Run Serva as Administrator:

| Setting | Field | Value |
| :--- | :--- | :--- |
| **DHCP Server** | Mode | Checked (**DO NOT** check proxyDHCP) |
| **DHCP Server** | Bind address | `128.173.94.81` |
| **DHCP Server** | IP Pool 1st addr / Size | `<TARGET_MACHINE_IP>` / Pool size = `1` |
| **DHCP Server** | Next Server (`siaddr`) | `128.173.94.81` (Serva itself) |
| **DHCP Server** | Boot File | `bootx64.efi` |
| **DHCP Server** | Subnet / Gateway / DNS | `255.255.252.0` / `128.173.92.1` / `198.82.247.66` |
| **DHCP Server** | MAC Filter | `accept` with only target MAC address (e.g. `AC:B4:80:3A:3A:82`) |
| **TFTP Server** | Root directory | `C:\Serva\netboot\amd64\` (Read Only, Port 69) |

#### Netboot File Hierarchy (`C:\Serva\netboot\amd64\`)
Extracted from `ubuntu-26.04-netboot-amd64.tar.gz`:
- `bootx64.efi` (966,768 bytes)
- `grubx64.efi` (2,418,568 bytes)
- `linux` (17,275,272 bytes)
- `initrd` (99,722,544 bytes)
- `grub\grub.cfg` (from [`grub.cfg.template`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/grub.cfg.template))

> [!CRITICAL]
> In `grub.cfg`, the `ds=nocloud-net;s=...` argument **MUST** be enclosed in double quotes. Unquoted, GRUB interprets `;` as a command separator and drops into interactive mode. Furthermore, `ramdisk_size=6G` is mandatory to avoid out-of-memory errors while unpacking the live ISO in RAM.

### B. LXC 210 Services (`198.82.18.151`)

1. **Seed Hosting (Nginx Port 80):**
   Files reside in `/srv/autoinstall/<machine>/`:
   - `user-data` (generated from [`user-data.template`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/user-data.template))
   - `meta-data` (empty 0-byte file created with `touch meta-data`)
2. **Install-Status Webhook Logger (Port 5001):**
   - Script: `/opt/status-api.py` ([`status-api.py`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/status-api.py))
   - Unit: `/etc/systemd/system/status-api.service` ([`status-api.service`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/status-api.service))
   - Monitor live progress:
     ```bash
     tail -f /var/log/install-status.log
     ```
3. **Firewall Rules (`/etc/pve/firewall/210.fw`):**
   Must allow TCP ports 80 and 5001 from `+approved-subnets`.

---

## 5. Autoinstall Rules & Limitations

Learned from direct test runs:
- **Disk Selection:** `storage.layout.match.size: largest` safely selects the 1TB Samsung SSD and leaves the 256GB Micron Windows drive untouched.
- **NVIDIA Drivers:** Set `drivers.install: false`. Installing proprietary GPU drivers during unattended install can stall on Secure Boot MOK password prompts.
- **Desktop Environment:** **DO NOT** place `ubuntu-desktop` under `packages:` or `late-commands:`. Subiquity crashes with exit status 100 under `unshare`/`systemd-run`. Install the desktop manually via SSH post-install:
  ```bash
  sudo apt-get update && sudo apt-get install -y ubuntu-desktop
  sudo systemctl set-default graphical.target
  ```
- **Secrets Sanitization:** Never commit user password hashes or DDNS tokens in plain text in git.

---

## 6. Execution & Monitoring Playbook

### Step 1: Pre-Flight Check on Windows Target
- Suspend BitLocker if active: `manage-bde -protectors -disable C: -RebootCount 2`
- Run [`switch-ahci.ps1`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/switch-ahci.ps1) and verify AHCI mode.

### Step 2: Stage Seed on LXC 210
```bash
# On node01:
pct exec 210 -- mkdir -p /srv/autoinstall/<MACHINE>/
pct exec 210 -- touch /srv/autoinstall/<MACHINE>/meta-data
# Push user-data and verify HTTP 200
pct exec 210 -- curl -I http://198.82.18.151/autoinstall/<MACHINE>/user-data
```

### Step 3: Configure Serva on `wvt465-xeon`
- Set IP pool to target IP, set MAC filter to target MAC, verify `grub.cfg`, and restart Serva as Administrator.

### Step 4: Trigger One-Time PXE Boot
Run [`trigger-pxe.ps1`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/trigger-pxe.ps1) in elevated PowerShell on the target machine:
```powershell
& "C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe" --ForcePxeNextBoot=Enabled
shutdown /r /t 0
```

### Step 5: Monitor Installation
- **Serva GUI Log on `wvt465-xeon`:** Verify DHCP lease and TFTP downloads (`bootx64.efi`, `grubx64.efi`, `grub.cfg`, `linux`, `initrd`).
- **LXC 210 Status Log:**
  ```bash
  pct exec 210 -- tail -f /var/log/install-status.log
  ```
- Install completes in ~7 minutes and issues an automatic reboot into Ubuntu.

---

## 7. Dual-Boot Boot Lockout Recovery

### The Circular Lockout Trap
If `GRUB_DEFAULT=saved` is configured in `/etc/default/grub`, switching to Windows causes GRUB to record Windows in `saved_entry` in `/boot/grub/grubenv`.
Because `grubenv` resides on an **ext4 partition** (`Disk 1, Partition 2`), Windows natively cannot modify it. Every subsequent reboot loops into Windows indefinitely.

### Safe Switching (Prevention)
Always switch to Windows using one-time flags that automatically clear on reboot:
```bash
# In Ubuntu:
sudo boot-windows
# (Which runs: efibootmgr -n <WINDOWS_HEX_BOOT_ID> && sudo reboot)
```

### Recovery from Windows ([`recover-boot-lockout.ps1`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/recover-boot-lockout.ps1))
If trapped in Windows:
1. Open PowerShell as Administrator.
2. Run [`recover-boot-lockout.ps1`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/recover-boot-lockout.ps1).
3. The script sets the secondary disk offline in Windows, passes it into WSL2 (`wsl --mount --bare`), clears `saved_entry` via `grub-editenv`, restores `GRUB_DEFAULT=0`, detaches the drive, brings it online, and reboots back into Ubuntu.

---

## 8. Troubleshooting Matrix

| Symptom | Root Cause | Solution |
| :--- | :--- | :--- |
| **Target boots to Windows; no TFTP in Serva** | Cross-subnet DHCP broadcast dropped | Ensure Serva is running on `128.173.94.81` on the same `/22` subnet with target MAC filtered |
| **Subiquity stops at interactive language screen** | Unquoted `ds=nocloud-net;s=...` in `grub.cfg` | Enclose the entire `ds=...` string in double quotes |
| **`wget: short write: No space left on device`** | Virtual ramdisk ran out of memory | Set `ramdisk_size=6G` in `grub.cfg` |
| **`Failed to find matching device` / `lsblk` empty** | Intel VMD hiding NVMe disks under RAID mode | Pre-stage AHCI drivers and switch BIOS to AHCI via [`switch-ahci.ps1`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/switch-ahci.ps1) |
| **`ubuntu-desktop` fails with exit status 100** | Subiquity sandbox crash on large package sets | Omit desktop from seed; install manually post-boot |
| **Status log empty / port 5001 timeout** | Port 5001 dropped by container firewall | Allow port 5001 from `+approved-subnets` in `/etc/pve/firewall/210.fw` |
| **Trapped in Windows; cannot boot Ubuntu** | `grubenv` ext4 file has `saved_entry` pointing to Windows | Run [`recover-boot-lockout.ps1`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/provisioning/recover-boot-lockout.ps1) via WSL2 |
