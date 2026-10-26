# CORNET Power Management & Wake-on-LAN

Scripts for configuring, managing, and triggering remote power on CORNET lab workstations.

---

## Tools

### 1. [`enable-wol.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/power/enable-wol.sh) — Workstation WoL Configuration
- **Purpose:** By default, Linux disables Wake-on-LAN (`wol d`) after reboot or power state changes. This script auto-detects the active campus ethernet interface, turns on MagicPacket (`wol g`) via `ethtool`, and configures persistent rules in `/etc/systemd/network/*.link` and `NetworkManager`.
- **Usage (run on workstation):**
  ```bash
  sudo ./enable-wol.sh
  ```
- **Prerequisites in BIOS/UEFI:**
  - Enable **Wake on LAN** or **Power On by PCI-E/PCI Device**.
  - Disable **Deep Sleep** / **EuP** / **ErP** (which powers down NIC PHY when the machine is shut down).

---

### 2. [`wake-node.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/power/wake-node.sh) — Remote Wake Trigger
- **Purpose:** Sends UDP broadcast MagicPackets to wake sleeping or powered-off workstations. Includes native Python fallback if `wakeonlan` or `etherwake` are not installed.
- **Usage (run from cluster node, server, or jump host on same subnet):**
  ```bash
  ./wake-node.sh <HOSTNAME_OR_MAC> [BROADCAST_IP]
  ```
- **Examples:**
  ```bash
  ./wake-node.sh wvt-wstation1 128.173.94.255
  ./wake-node.sh wvt465-xeon 128.173.94.255
  ./wake-node.sh 34:17:eb:de:5c:dd 128.173.94.255
  ```

### Verified Workstation MAC Address Table

| Hostname | Primary Interface | MAC Address | OS |
| :--- | :--- | :--- | :--- |
| `wvt-pratheek-pc-ubuntu` | `enp128s31f6` | `ac:b4:80:3a:3a:9e` | Ubuntu 24.04 / Windows Dual-Boot |
| `wvt-wstation1-ubuntu` | `enp128s31f6` | `ac:b4:80:3a:3a:82` | Ubuntu 24.04 / Windows Dual-Boot |
| `wvt-wstation3-ubuntu` | `enp128s31f6` | `ac:b4:80:3a:3a:51` | Ubuntu 24.04 |
| `wvt-nuc-02` | `enp0s31f6` | `58:47:ca:7c:1d:75` | Ubuntu 24.04 |
| `wvt465-xeon` | `Ethernet (I217-LM)` | `34:17:eb:de:5c:dd` | Windows 10 |
