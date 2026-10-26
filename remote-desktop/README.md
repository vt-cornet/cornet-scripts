# CORNET Remote Desktop Architecture (GNOME RDP)

Automated system-level RDP server setup for Ubuntu 24.04 and 26.04 lab workstations using **GNOME Remote Desktop**.

---

## Background & Architecture

In Ubuntu 24.04 LTS+, GNOME Remote Desktop replaces older X11-based solutions (e.g. NoMachine, XRDP, VNC) and operates natively under Wayland.

- **Port:** `3389/tcp` (Standard RDP port, identical to Windows).
- **Client Compatibility:** Compatible with Microsoft Remote Desktop (macOS, iOS, Windows, Android) and FreeRDP.
- **Daemon Mode:** Configured as a **system-wide daemon** (`/usr/libexec/gnome-remote-desktop-daemon --system`) rather than a per-user daemon, allowing headless connections to login screens without requiring an active physical display session.

---

## Setup Script ([`setup-gnome-rdp-system.sh`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/remote-desktop/setup-gnome-rdp-system.sh))

The setup script automates four critical configuration tasks:

1. **System TLS Certificates:** Generates a dedicated RSA 2048-bit certificate at `/etc/gnome-remote-desktop/rdp-tls.crt` owned by `gnome-remote-desktop:gnome-remote-desktop`.
2. **Non-Interactive Configuration:** Configures system credentials and disables view-only mode via `grdctl --system`.
3. **Per-User Daemon Suppression:** Masks `gnome-remote-desktop.service` globally across all user systemd sessions (`systemctl --global mask`) so SSH logins do not attempt to bind port 3389.
4. **Systemd Unit Management:** Enables and starts the system daemon (`systemctl enable --now gnome-remote-desktop.service`).

---

## Usage

```bash
sudo ./setup-gnome-rdp-system.sh <USERNAME> <RDP_PASSWORD>

# Example:
sudo ./setup-gnome-rdp-system.sh pratheek "MySecretPassword"
```

## Connecting

- **Address:** `<hostname>.cornet.wireless.vt.edu:3389`
- **Username:** `<USERNAME>`
- **Password:** `<RDP_PASSWORD>`
- **Security:** In Microsoft Remote Desktop, accept the self-signed TLS certificate prompt.
