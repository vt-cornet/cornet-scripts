# CORNET Scripts & Infrastructure Automation

Automation scripts, Dynamic DNS service, and declarative firewall configurations for the **CORNET Proxmox Cluster** and lab environment at Virginia Tech.

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
│       ├── update-ddns.ps1     # Windows PowerShell updater
│       └── CORNET-DDNS-Update.xml # Windows Task Scheduler definition
│
├── firewall/                   # Declarative Proxmox VE & workstation firewall configurations
│   ├── README.md               # Firewall architecture, IPSETs, and deployment guide
│   ├── cluster.fw              # Datacenter-level rules & approved subnet IPSETs
│   ├── setup-workstation-firewall.sh # Replicates cluster security on Ubuntu workstations (UFW)
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
├── remote-desktop/             # Ubuntu GNOME Remote Desktop (RDP) automation
│   ├── README.md               # Architecture, TLS certificate setup, and troubleshooting
│   └── setup-gnome-rdp-system.sh # Automated system-level daemon, TLS, and grdctl config
│
└── tools/                      # Lab workstation utilities
    ├── README.md               # Documentation for workstation tools
    ├── boot-windows.sh         # Dual-boot EFI switcher to reboot directly into Windows
    └── x310-ctl.sh             # USRP X310 smart plug AC power control
```

---

## Remote Access Architecture

- **Ubuntu Workstations (24.04 / 26.04):** Native **GNOME Remote Desktop** system daemon (`gnome-remote-desktop.service`) serving RDP on port `3389`. (Replaced NoMachine and RustDesk for superior native Wayland performance).
- **Windows Workstations:** Native **Windows Remote Desktop (RDP)** on port `3389`.
- **Proxmox Cluster & Guests:** Secured behind the `firewall/` IPSETs allowing RDP and SSH exclusively from `approved-subnets` and the VT campus VPN.


---

## Core Components

### 1. Cluster Node Onboarding ([`node-setup.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/node-setup.sh))
Automates baseline configuration when adding new nodes to the Proxmox cluster:
- Disables enterprise repositories and configures `pve-no-subscription` and Ceph Quincy repositories.
- Performs full package updates (`apt-get dist-upgrade`).
- Suppresses the web UI "No Subscription" nag popup and installs a persistent `dpkg` hook.
- Deploys the official CORNET MOTD.

**One-line installation:**
```bash
bash <(curl -s https://raw.githubusercontent.com/vt-cornet/cornet-scripts/main/node-setup.sh)
```

### 2. Dynamic DNS Service ([`ddns/`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/ddns))
Maintains consistent DNS resolution for lab machines with dynamic IP addresses under `*.cornet.wireless.vt.edu`:
- **Server:** Hosted on LXC container `200` (`198.82.18.150`). Exposes `/update` endpoint validated against a whitelist of authorized hostnames and token.
- **Clients:** Automated scripts for Linux (systemd timer) and Windows (Task Scheduler) to report active IPs to the server.

### 3. Cluster Firewall ([`firewall/`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall))
Declarative rules applied via Proxmox cluster filesystem (`/etc/pve/firewall/`):
- Restricts cluster management ports (SSH `22`, GUI `8006`) to `approved-subnets`.
- Restricts Corosync cluster heartbeat traffic (`5405:5406/udp`) to verified `cluster-nodes`.
- Isolates guest VMs from cluster management interfaces with MAC/IP anti-spoofing filters.
