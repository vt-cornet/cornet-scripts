# CORNET Workstation & Hardware Control Tools

Utility scripts deployed across CORNET lab workstations and hardware controllers.

---

## Tools

> [!NOTE]
> SDR hardware power control utilities (for both Ettus X310 and N310) are now organized under [`sdr-control/`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/sdr-control/README.md).

### 1. [`boot-windows.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/tools/boot-windows.sh) — Dual-Boot EFI Switcher
- **Location on Host:** `/usr/local/bin/boot-windows` (deployed on dual-boot Ubuntu workstations)
- **Purpose:** Inspects EFI boot options using `efibootmgr`, selects the "Windows Boot Manager" entry, sets it as the one-time `BootNext` target, and reboots the machine directly into Windows.
- **Usage:**
  ```bash
  sudo boot-windows
  ```

---

### 2. [`x310-ctl.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/sdr-control/x310-ctl.sh) — USRP X310 Smart Plug Power Control (Symlink)
- **Primary Location:** [`sdr-control/x310-ctl.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/sdr-control/x310-ctl.sh) (symlinked from `tools/x310-ctl.sh`)
- **Documentation:** See [`sdr-control/README.md`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/sdr-control/README.md)

---

### 3. [`setup-workstation-tuning.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/tools/setup-workstation-tuning.sh) — Workstation Kernel, Power, Network & Time Tuning
- **Location on Host:** Installed and run via `sudo ./setup-workstation-tuning.sh`
- **Purpose:** Automates essential system hardening and SDR streaming performance optimizations for headless lab workstations:
  1. **Sleep & Suspend Masking:** Masks all systemd sleep/suspend/hibernate targets and suppresses GDM/GNOME idle timeouts to prevent workstations from dropping network connectivity.
  2. **Auto-Reboot on Kernel Panic:** Configures `kernel.panic = 10` in `/etc/sysctl.d/99-panic.conf` so unhandled driver/NIC crashes reboot in 10 seconds rather than hanging frozen.
  3. **High-Precision NTP via Chrony:** Configures chrony to peer with Virginia Tech's authoritative Stratum-2 NTP servers (`198.82.247.66`, `198.82.247.98`) achieving sub-microsecond synchronization required for 5G/O-RAN testbeds.
  4. **SDR Kernel Socket Buffers:** Sets 64MB socket buffers (`rmem_max=67108864`, `wmem_max=67108864`) in `/etc/sysctl.d/99-uhd.conf` to eliminate UHD packet drops (`D`) and buffer overflows (`O`).
  5. **10GbE Ring Buffers:** Expands hardware ring descriptors to `rx 4096 tx 4096` and ensures MTU 9000 on SDR SFP+ interfaces, with persistent boot service (`cornet-sdr-ringbuffers.service`).
- **Usage:**
  ```bash
  sudo ./tools/setup-workstation-tuning.sh
  ```

---

### 4. [`setup-windows-ssh.ps1`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/tools/setup-windows-ssh.ps1) — Windows OpenSSH Server Setup & Key Authorization
- **Location on Host:** Run in PowerShell as Administrator on Windows 10/11
- **Purpose:** 
  1. Installs the native Windows `OpenSSH.Server` capability.
  2. Sets `sshd` service to automatic startup and starts the service.
  3. Pre-authorizes the lab ED25519 SSH public key in both `C:\ProgramData\ssh\administrators_authorized_keys` and the user profile `~\.ssh\authorized_keys`.
  4. Enforces strict NTFS permissions (inheritance removed; full control granted exclusively to `SYSTEM` and `Administrators`) to satisfy OpenSSH security requirements.
  5. Opens port 22 in Windows Defender Firewall.
- **Usage (PowerShell as Admin):**
  ```powershell
  powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/tools/setup-windows-ssh.ps1 | iex"
  ```
