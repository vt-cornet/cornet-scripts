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

### 2. [`boot-windows.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/tools/boot-windows.sh) — Dual-Boot EFI Switcher
- **Location on Host:** `/usr/local/bin/boot-windows` (deployed on dual-boot Ubuntu workstations)
- **Purpose:** Inspects EFI boot options using `efibootmgr`, selects the "Windows Boot Manager" entry, sets it as the one-time `BootNext` target, and reboots the machine directly into Windows.
- **Usage:**
  ```bash
  sudo boot-windows
  ```
