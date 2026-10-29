# CORNET Scripts & Infrastructure Automation

Automation scripts, Dynamic DNS service, and declarative firewall configurations for the **CORNET Proxmox Cluster** and lab environment at Virginia Tech.

> [!TIP]
> **Complete Documentation Website:**
> Comprehensive system guides, operational runbooks, hypervisor cluster topologies, and troubleshooting matrices are documented in the [CORNET Infrastructure Docs](../cornet-infrastructure-docs).

---

## Repository Structure

```
.
├── node-setup.sh               # Post-install onboarding script for Proxmox cluster nodes
├── cornet-motd.sh              # Standardized CORNET MOTD login banner
│
├── ddns/                       # Dynamic DNS service for lab machines (*.cornet.wireless.vt.edu)
│   ├── README.md               # DDNS service documentation and API reference
│   ├── server/                 # DDNS backend (LXC 200: dns-server)
│   │   ├── app.py              # Flask DDNS update API
│   │   ├── register-node.sh    # CLI tool to register a new node in whitelist & dnsmasq
│   │   ├── ddns-api.service    # Systemd service unit for Gunicorn
│   │   ├── ddns-api.env.example# Environment template for authorization token
│   │   ├── dnsmasq.conf        # Authoritative dnsmasq configuration & static records
│   │   └── requirements.txt    # Python dependencies
│   └── client/                 # Periodic boot updater scripts for lab workstations
│       ├── setup-ddns-client.sh # One-line client onboarding & systemd installer
│       ├── update-ddns.sh      # Linux bash updater (Hardened Multi-Interface Edition)
│       ├── cornet-ddns.service # Linux systemd service unit
│       ├── update-ddns.ps1     # Windows PowerShell updater (Dual-boot workstations)
│       ├── update-ddns-xeon.ps1# Windows PowerShell updater (Dedicated for wvt465-xeon)
│       ├── CORNET-DDNS-Update.xml # Windows Task Scheduler XML (On-boot trigger)
│       └── CORNET-DDNS-Update-Xeon.xml # Windows Task Scheduler XML (3-hour repeating trigger)
│
├── firewall/                   # Declarative Proxmox VE & workstation firewall configurations
│   ├── README.md               # Firewall architecture, IPSETs, and deployment guide
│   ├── cluster.fw              # Datacenter-level rules & approved subnet IPSETs
│   ├── setup-workstation-firewall.sh # Replicates cluster security on Ubuntu workstations (UFW)
│   ├── setup-windows-firewall.ps1 # Replicates cluster security on Windows 10/11 (Defender)
│   └── guests/                 # Per-VM and per-container firewall rules
│       ├── 200.fw              # DNS Server (LXC 200)
│       ├── 210.fw              # PXE Provisioning Server (LXC 210)
│       ├── 220.fw              # RustDesk Remote Desktop (LXC 220)
│       ├── 230.fw              # Headscale WireGuard VPN (LXC 230)
│       ├── 299.fw              # PXE Securetest VM (VM 299)
│       ├── 100.fw - 103.fw     # Research Compute VMs
│       └── 9040.fw, 9099.fw    # Golden VM Templates
│
├── power/                      # Workstation power management & Wake-on-LAN
│   ├── README.md               # WoL setup instructions, BIOS prerequisites, and wake guide
│   ├── enable-wol.sh           # Persistent workstation WoL configuration (systemd-networkd/NM)
│   └── wake-node.sh            # Remote MagicPacket wake trigger CLI
│
├── provisioning/               # Bare-metal UEFI PXE autoinstall for Dell T2 workstations
│   ├── README.md               # Complete architecture, Serva config, pre-flight & recovery guide
│   ├── status-api.py           # Subiquity install-status webhook logger (Port 5001 on LXC 210)
│   ├── status-api.service      # Systemd service unit for status-api.py
│   ├── user-data.template      # Subiquity unattended autoinstall seed (size: largest)
│   ├── grub.cfg.template       # Serva GRUB netboot menu (ramdisk_size=6G, quoted ds=)
│   ├── switch-ahci.ps1         # Windows AHCI driver pre-staging & CCTK BIOS storage switch
│   ├── trigger-pxe.ps1         # Windows one-time UEFI PXE boot arming CLI (CCTK/bcdedit)
│   └── recover-boot-lockout.ps1# WSL2 ext4 raw mount rescue script for Windows boot loops
│
├── remote-desktop/             # Ubuntu GNOME Remote Desktop (RDP) automation
│   ├── README.md               # Architecture, TLS certificate setup, and troubleshooting
│   ├── setup-gnome-rdp-system.sh # Automated system-level daemon, TLS, and grdctl config
│   └── fix-gnome-rdp.sh        # FreeRDP library rollback & macOS client handshake fix
│
├── student-vms/                # Golden template + per-student KVM VMs for course sessions
│   ├── README.md               # Build, seal, clone, validate, hand-out and teardown guide
│   ├── clone-advcell.sh        # Clone student VMs from template 9040 (static IP, firewall, CSV creds)
│   ├── grd-firstboot.sh        # Per-VM GNOME Remote Desktop TLS key (first boot)
│   ├── grd-firstboot.service   # Systemd one-shot unit for the above
│   ├── 99-renderer-networkd.yaml # netplan override: keep networkd after installing the desktop
│   └── student-vm.fw.template  # Per-VM Proxmox firewall template
│
├── sdr-control/                # Software Defined Radio (SDR) hardware power & diagnostics
│   ├── README.md               # Architecture guide for Ettus X310 and N310 SDRs
│   ├── n310-ctl.sh             # USRP N310 safe shutdown, reboot, detection & MCU powerbtn simulation
│   └── x310-ctl.sh             # USRP X310 Shelly smart plug AC relay control
│
└── tools/                      # Lab workstation utilities
    ├── README.md               # Documentation for workstation tools
    ├── boot-windows.sh         # Dual-boot EFI switcher to reboot directly into Windows
    ├── setup-workstation-tuning.sh # Automated kernel, power, network & chrony NTP tuning
    ├── setup-windows-ssh.ps1   # Windows OpenSSH Server setup & key authorization
    └── x310-ctl.sh             # Symlink to sdr-control/x310-ctl.sh
```

---

## Remote Access Architecture

- **Ubuntu Workstations (24.04 / 26.04):** Native **GNOME Remote Desktop** system daemon (`gnome-remote-desktop.service`) serving RDP on port `3389`. (Replaced NoMachine and RustDesk for superior native Wayland performance).
- **Windows Workstations:** Native **Windows Remote Desktop (RDP)** on port `3389`.
- **Proxmox Cluster & Guests:** Secured behind the `firewall/` IPSETs allowing RDP and SSH exclusively from `approved-subnets` and the VT campus VPN.


---

## Core Components

### 1. Cluster Node Onboarding ([`node-setup.sh`](node-setup.sh))
Automates baseline configuration when adding new nodes to the Proxmox cluster:
- Disables enterprise repositories and configures `pve-no-subscription` and Ceph Quincy repositories.
- Performs full package updates (`apt-get dist-upgrade`).
- Suppresses the web UI "No Subscription" nag popup and installs a persistent `dpkg` hook.
- Deploys the official CORNET MOTD.

**One-line installation:**
```bash
bash <(curl -s https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/node-setup.sh)
```

### 2. Dynamic DNS Service ([`ddns/`](ddns/))
Maintains consistent DNS resolution for lab machines with dynamic IP addresses under `*.cornet.wireless.vt.edu`:
- **Server:** Hosted on LXC container `200` (`198.82.18.150`). Exposes `/update` endpoint validated against a whitelist of authorized hostnames and token.
- **Clients:** Automated scripts for Linux (systemd timer) and Windows (Task Scheduler) to report active IPs to the server.

### 3. Cluster Firewall ([`firewall/`](firewall/))
Declarative rules applied via Proxmox cluster filesystem (`/etc/pve/firewall/`):
- Restricts cluster management ports (SSH `22`, GUI `8006`) to `approved-subnets`.
- Restricts Corosync cluster heartbeat traffic (`5405:5406/udp`) to verified `cluster-nodes`.
- Isolates guest VMs from cluster management interfaces with MAC/IP anti-spoofing filters.

### 4. Bare-Metal PXE Provisioning ([`provisioning/`](provisioning/))
Automates unattended bare-metal UEFI PXE deployment of Ubuntu onto Dell Pro Max Tower T2 workstations:
- **Cross-Subnet PXE Relay:** Local DHCP/TFTP serving from `wvt465-xeon` via Serva to bypass campus DHCP relay limitations.
- **Hardware Pre-staging:** Registry preparation and Dell CCTK storage mode switching from RAID (Intel VMD) to AHCI.
- **Subiquity Autoinstall:** Automated seed delivery (`user-data`) with live HTTP webhook progress telemetry to LXC 210.
- **Dual-Boot Safety:** Safe one-time boot switching via `boot-windows` and WSL2 physical disk rescue script for Windows boot loops.

### 5. Student Course VMs ([`student-vms/`](student-vms/))
Builds a sealed Ubuntu golden VM on `cornet-node04` and clones one CPU-pinned, firewalled KVM VM per student (static IP, SSH + GNOME RDP over the VT VPN) for hands-on sessions such as OAI/FlexRIC/xApp development:
- **Template + clones:** cloud-init static addressing, per-VM random credentials in a root-only CSV, per-VM TLS key for RDP.
- **Isolation:** per-VM firewall with MAC/IP anti-spoofing and a node block, tracked in `firewall/guests/`.
- **Operational notes:** quorum gating for a cluster with no margin, and the lessons learned from the first build.

### 6. Workstation Power & Wake-on-LAN ([`power/`](power/))
Enables remote power cycling and cold startup across Dell Precision and Xeon lab machines:
- **`enable-wol.sh`:** Persistent WoL configuration (`ethtool -s eth0 wol g`) across reboot cycles via NetworkManager or systemd-networkd.
- **`wake-node.sh`:** Remote wake CLI broadcasting targeted UDP magic packets across lab subnets.

### 7. Remote Desktop Automation ([`remote-desktop/`](remote-desktop/))
Configures native system-level GNOME Remote Desktop (RDP) on headless and graphical workstations:
- **`setup-gnome-rdp-system.sh`:** Automated systemd daemon configuration, TLS certificate generation, and port 3389 binding.
- **`fix-gnome-rdp.sh`:** Client handshake patch for macOS and cross-platform FreeRDP interoperability.

### 8. SDR Control & Smart Plugs ([`sdr-control/`](sdr-control/))
Hardware management utilities for software-defined radios:
- **`x310-ctl.sh`:** Automated power-cycling for Ettus USRP X310 units connected to Shelly smart plug relays.
- **`n310-ctl.sh`:** Safe shutdown, detection, and simulated MCU power button toggle for Ettus USRP N310 units over SSH.

### 9. Workstation Utilities & Performance Tuning ([`tools/`](tools/))
Host management and performance tuning scripts:
- **`setup-workstation-tuning.sh`:** Applies CPU governor (`performance`), TCP buffer expansions, PCIe ASPM disablement, and low-latency Chrony NTP synchronization.
- **`boot-windows.sh`:** One-time EFI boot selection tool to cleanly reboot a dual-boot workstation into Windows from Linux.
- **`setup-windows-ssh.ps1`:** Installs and secures Windows OpenSSH Server for automated administration.
