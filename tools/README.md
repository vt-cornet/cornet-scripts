# CORNET Workstation & Hardware Control Tools

Utility scripts deployed across CORNET lab workstations and hardware controllers.

---

## Tools

### 1. [`x310-ctl.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/tools/x310-ctl.sh) — USRP X310 Smart Plug Power Control
- **Location on Host:** `/usr/local/bin/x310-ctl` (deployed on `wvt-nuc-02`)
- **Purpose:** Programmatically controls AC power to Ettus USRP X310 SDRs via local Shelly Gen4 smart plugs over the private management LAN (`192.168.8.x`).
- **Hardware Map:**
  - `X310 #1` -> Shelly Plug 1 (`192.168.8.50`, MAC: `AC:EB:E6:F5:1F:60`) -> attached to `wvt-nuc-02`
  - `X310 #2` -> Shelly Plug 2 (`192.168.8.51`, MAC: `AC:EB:E6:F3:D1:74`) -> attached to `wvt-wstation3-ubuntu`
- **Commands:**
  ```bash
  x310-ctl status [1|2|all]      # Query current power and relay status
  x310-ctl on     [1|2|all]      # Turn on SDR power
  x310-ctl off    [1|2|all] [-y] # Turn off SDR power (with confirmation prompt)
  x310-ctl cycle  [1|2|all] [-y] # Power-cycle SDR (10-second wait between off and on)
  ```

---

### 2. [`boot-windows.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/tools/boot-windows.sh) — Dual-Boot EFI Switcher
- **Location on Host:** `/usr/local/bin/boot-windows` (deployed on dual-boot Ubuntu workstations)
- **Purpose:** Inspects EFI boot options using `efibootmgr`, selects the "Windows Boot Manager" entry, sets it as the one-time `BootNext` target, and reboots the machine directly into Windows.
- **Usage:**
  ```bash
  sudo boot-windows
  ```
