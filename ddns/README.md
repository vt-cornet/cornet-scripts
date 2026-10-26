# CORNET Dynamic DNS (DDNS) Service

Automated Dynamic DNS service for the CORNET Proxmox cluster and lab machines (`*.cornet.wireless.vt.edu`).

## Overview

The DDNS service enables lab workstations and servers with dynamic campus IP addresses to maintain consistent, resolvable FQDNs across the Virginia Tech network.

- **DNS Server Container:** Proxmox LXC container `200` (`dns-server`) running Debian/Ubuntu.
- **Internal / External IPs:** `10.10.0.3` (vmbr1) / `198.82.18.150` (vmbr0).
- **Resolver Backend:** `dnsmasq` authoritative for `cornet.wireless.vt.edu`.
- **API Service:** Python Flask API served by `gunicorn` on port `5000` (`/health`, `/update`).

```
 +-----------------------------------+
 |  Lab Workstations / Servers       |
 |  (Ubuntu / Windows / NUCs)        |
 +-----------------+-----------------+
                   |
         HTTP POST /update (JSON)
                   v
 +-----------------------------------+
 |  cornet-node01 -> LXC 200         |
 |  198.82.18.150:5000 (DDNS API)    |
 +-----------------+-----------------+
                   | updates /etc/dnsmasq.conf
                   v
 +-----------------------------------+
 |  dnsmasq                          |
 |  *.cornet.wireless.vt.edu         |
 +-----------------------------------+
```

---

## Directory Structure

```
ddns/
├── server/
│   ├── app.py                 # Flask API handling /health and /update
│   ├── register-node.sh       # CLI tool to register a new node in whitelist & dnsmasq
│   ├── ddns-api.service       # Systemd service unit for Gunicorn
│   ├── ddns-api.env.example   # Environment file template for token & configs
│   ├── dnsmasq.conf           # Authoritative dnsmasq configuration & static records
│   └── requirements.txt       # Python dependencies (Flask, gunicorn)
└── client/
    ├── update-ddns.sh         # Linux updater (Hardened Multi-Interface Edition)
    ├── cornet-ddns.service    # Linux systemd boot service
    ├── update-ddns.ps1        # Windows PowerShell updater (with boot retry loop)
    └── CORNET-DDNS-Update.xml # Windows Task Scheduler definition
```

---

## Node Registration (`register-node.sh`)

To register a new workstation or server in the DDNS whitelist:

```bash
# Can be executed on cornet-node01 or directly inside LXC 200:
./register-node.sh <HOSTNAME> [INITIAL_IP]

# Example:
./register-node.sh wvt-gnuc-03 128.173.94.103
```
*Automatically validates formatting, appends the hostname to `ALLOWED_HOSTNAMES` in `app.py`, updates `dnsmasq.conf`, restarts `ddns-api` and `dnsmasq`, and confirms API health.*


---

## API Specification

### Health Check

- **URL:** `GET http://198.82.18.150:5000/health`
- **Response:**
  ```json
  {"status": "ok"}
  ```

### Update DNS Record

- **URL:** `POST http://198.82.18.150:5000/update`
- **Headers:** `Content-Type: application/json`
- **Request Body:**
  ```json
  {
    "token": "<SHARED_SECRET_TOKEN>",
    "hostname": "wvt-wstation1-ubuntu",
    "ip": "128.173.94.17"
  }
  ```
- **Validation Rules:**
  - Token must match the configured `DDNS_TOKEN`.
  - Hostname must be in `ALLOWED_HOSTNAMES` whitelist.
  - IP must be a valid IPv4 address (regex + octet boundary validation).
- **Response (200 OK):**
  ```json
  {
    "status": "ok",
    "hostname": "wvt-wstation1-ubuntu.cornet.wireless.vt.edu",
    "ip": "128.173.94.17"
  }
  ```

---

## Allowed Hostnames

Only pre-registered hostnames in `app.py` may be updated:
- `wvt465-xeon`
- `wvt-pratheek-pc-win`
- `wvt-pratheek-pc-ubuntu`
- `wvt-wstation1-win`, `wvt-wstation1-ubuntu`
- `wvt-wstation2-win`, `wvt-wstation2-ubuntu`
- `wvt-wstation3-ubuntu`
- `wvt-nuc-01`, `wvt-nuc-02`
- `wvt-gnuc-02`, `wvt-gnuc-05`
- `wvt-wsalpha`
- `wvt-propsim`
- `cornet-rustdesk`
- `wvt-headscale`

---

## Client Scripts (Ubuntu)

The workstation client scripts publish the machine's dynamic IP to the DDNS server on boot.

- **Script:** [`client/update-ddns.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/ddns/client/update-ddns.sh) (deployed to `/opt/cornet/update-ddns.sh`)
- **Systemd Service:** [`client/cornet-ddns.service`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/ddns/client/cornet-ddns.service) (deployed to `/etc/systemd/system/cornet-ddns.service`)

### Installation on Ubuntu Workstation

```bash
sudo mkdir -p /opt/cornet
sudo cp update-ddns.sh /opt/cornet/update-ddns.sh
sudo chmod +x /opt/cornet/update-ddns.sh

sudo cp cornet-ddns.service /etc/systemd/system/cornet-ddns.service
sudo systemctl daemon-reload
sudo systemctl enable cornet-ddns.service
sudo systemctl start cornet-ddns.service
```

### Evolution / Version Differences
- **Initial Version (`wvt-pratheek-pc-ubuntu`):** Performed a single instantaneous `curl` POST on boot.
- **Latest Version (`wvt-wstation1-ubuntu` / `wvt-nuc-02`):** Added a 5-attempt retry loop with 5-second backoff, `@` interface trimming (`cut -d'@' -f1`), kernel routing resolution (`ip route get`), Wi-Fi avoidance, and smart-plug LAN isolation.

---

## Client Scripts (Windows)

- **Script:** [`client/update-ddns.ps1`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/ddns/client/update-ddns.ps1) (deployed to `C:\ProgramData\CORNET\update-ddns.ps1`)
- **Task Scheduler XML:** [`client/CORNET-DDNS-Update.xml`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/ddns/client/CORNET-DDNS-Update.xml)

### Installation on Windows Workstation

1. Place the script in `C:\ProgramData\CORNET\update-ddns.ps1`:
   ```powershell
   New-Item -ItemType Directory -Path "C:\ProgramData\CORNET" -Force
   Copy-Item .\update-ddns.ps1 -Destination "C:\ProgramData\CORNET\update-ddns.ps1"
   ```

2. Register the Windows Scheduled Task (runs on boot as `SYSTEM`):
   ```cmd
   schtasks /Create /TN "CORNET-DDNS-Update" /XML "CORNET-DDNS-Update.xml" /F
   ```



