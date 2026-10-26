#!/usr/bin/env bash
# Per-VM GNOME Remote Desktop first-boot setup (runs once per clone as root, via grd-firstboot.service).
# Generates a unique TLS key/cert per VM so clones never share one. The RDP username/password is set
# afterwards from the Proxmox node with: grdctl --system rdp set-credentials student "<password>"
set -euo pipefail
D=/var/lib/gnome-remote-desktop
[ -f $D/rdp.key ] && exit 0
install -d -o gnome-remote-desktop -g gnome-remote-desktop -m 0750 $D
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
  -subj "/CN=$(hostname -f)" -out $D/rdp.crt -keyout $D/rdp.key
chown gnome-remote-desktop:gnome-remote-desktop $D/rdp.crt $D/rdp.key
chmod 0600 $D/rdp.key
grdctl --system rdp set-tls-cert $D/rdp.crt
grdctl --system rdp set-tls-key $D/rdp.key
grdctl --system rdp enable
systemctl enable gnome-remote-desktop.service
systemctl start --no-block gnome-remote-desktop.service
