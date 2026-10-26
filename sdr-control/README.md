# CORNET SDR Control (`sdr-control/`)

Remote power management, device detection, and diagnostics for Software Defined Radios (Ettus USRP X310 and USRP N310) deployed in the CORNET testbed.

---

## Hardware Overview & Comparison

| Characteristic | Ettus USRP X310 | Ettus USRP N310 |
| :--- | :--- | :--- |
| **Architecture** | FPGA-only (Kintex-7) | Embedded Linux on dual-core ARM Cortex-A9 + Kintex UltraScale+ FPGA + STM32 MCU |
| **Operating System** | None (Firmware only) | Embedded Linux (Yocto / OpenEmbedded) |
| **Power Control Method** | AC relay control via Shelly Gen4 Smart Plug API | Network SSH clean shutdown (`shutdown -h now`) / STM32 microcontroller UART (`powerbtn`) |
| **Abrupt Power Cut Risk** | Safe (FPGA simply loses power) | **HIGH RISK:** Filesystem corruption on internal eMMC/NAND |
| **Auto-Power On** | Always boots when AC power is applied | Configurable via EEPROM flag (`eeprom-set-flags 0x1`) |
| **CORNET Deployments** | `wvt-nuc-02` (Plug 1: `192.168.8.50`), `wvt-wstation3` (Plug 2: `192.168.8.51`) | `wvt-wstation3` (`192.168.20.2`, Serial `3196923`), `wvt-nuc-02` (`192.168.20.2`, Serial `319692B`) |

---

## 1. USRP N310 Control ([`n310-ctl.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/sdr-control/n310-ctl.sh))

Reference: [Ettus USRP N300/N310 Getting Started Guide](https://kb.ettus.com/USRP_N300/N310/N320/N321_Getting_Started_Guide#Connecting_to_the_ARM_via_SSH)

Because the N310 runs a full embedded Linux operating system, powering down the unit by cutting AC power can corrupt the filesystem. `n310-ctl.sh` provides safe remote shutdown, rebooting, device detection, and power button emulation.

### Commands

```bash
# Check reachability via ICMP, SSH, and uhd_find_devices
./sdr-control/n310-ctl.sh status [192.168.20.2]

# Perform a safe, clean shutdown of the embedded Linux OS
./sdr-control/n310-ctl.sh shutdown [192.168.20.2] [-y]

# Reboot the ARM processor and reload the FPGA
./sdr-control/n310-ctl.sh reboot [192.168.20.2] [-y]

# Enable Auto-Boot on AC power in the onboard EEPROM
./sdr-control/n310-ctl.sh auto-boot [192.168.20.2]

# Run full RF frontend and clock probe
./sdr-control/n310-ctl.sh probe [192.168.20.2]

# Simulate physical power button press via USB console (STM32 microcontroller)
./sdr-control/n310-ctl.sh powerbtn [/dev/serial/by-id/*-if01*]
```

### Microcontroller & Power Button Details

- **ARM Serial vs. MCU Serial:** When the micro-USB console cable is connected to the host, the CP2105 dual-UART bridge exposes two interfaces:
  - `if00` / `/dev/ttyUSB0`: ARM Linux serial console.
  - `if01` / `/dev/ttyUSB1`: STM32 Microcontroller console.
- **Power Button Emulation:** Typing `powerbtn` over the STM32 UART console (at 115200 baud) emulates pressing the physical front-panel power button. This can turn the unit on from standby or initiate a power transition without physical access.
- **Auto-Boot Configuration:** Setting `eeprom-set-flags 0x1` instructs the STM32 microcontroller to automatically boot the ARM processor as soon as AC/DC power is applied, eliminating the need to physically press the power button after power interruptions.

---

## 2. USRP X310 Control ([`x310-ctl.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/sdr-control/x310-ctl.sh))

Controls AC power to Ettus USRP X310 SDRs using Shelly Gen4 smart plugs over the private smart plug network (`192.168.8.0/24`).

### Hardware Map

- **X310 #1:** Shelly Plug 1 (`192.168.8.50`, MAC: `AC:EB:E6:F5:1F:60`) attached to `wvt-nuc-02`.
- **X310 #2:** Shelly Plug 2 (`192.168.8.51`, MAC: `AC:EB:E6:F3:D1:74`) attached to `wvt-wstation3-ubuntu`.

### Commands

```bash
# Check relay status, active power draw, and voltage
./sdr-control/x310-ctl.sh status [1|2|all]

# Power on
./sdr-control/x310-ctl.sh on [1|2|all]

# Power off (prompts for confirmation unless -y is specified)
./sdr-control/x310-ctl.sh off [1|2|all] [-y]

# Power cycle (waits 10s for DC rail bleed before powering back on)
./sdr-control/x310-ctl.sh cycle [1|2|all] [-y]
```
