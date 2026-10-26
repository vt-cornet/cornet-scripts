#!/usr/bin/env bash
# Clone student VMs from the golden template on this Proxmox node.
#
# usage: START=<n> /root/clone-advcell.sh <ip> [<ip> ...]
#   START=1 -> first IP becomes advcell-vm1, next advcell-vm2, ...
#
# Run detached so a dropped SSH session cannot kill qemu-img:
#   setsid nohup env START=1 /root/clone-advcell.sh 128.173.88.211 > /root/clone-vm1.log 2>&1 < /dev/null &
#
# Writes name,vmid,user,password,ip to a root-only CSV. Never commit that file.
set -euo pipefail
umask 077

TEMPLATE=9040
STORAGE=local-zfs
CRED=/root/oai-vm-credentials.csv
GW=128.173.88.1
DNS=198.82.247.66
START=${START:-1}
AFFINITY=("4-11,100-107" "12-19,108-115" "20-27,116-123" "28-35,124-131" "36-43,132-139")

[ "$#" -ge 1 ] || { echo "usage: START=<n> $0 <ip> [<ip> ...]"; exit 1; }
IPS=("$@")

write_fw() {   # usage: write_fw <vmid> <ip>
  cat > /etc/pve/firewall/$1.fw <<EOF
[OPTIONS]
enable: 1
dhcp: 1
macfilter: 1
ipfilter: 1
policy_in: DROP
policy_out: ACCEPT

[IPSET ipfilter-net0]
$2

[RULES]
IN DROP -source +dc/cluster-nodes
OUT DROP -dest +dc/cluster-nodes
IN ACCEPT -source +dc/approved-subnets -p tcp -dport 22
IN ACCEPT -source +dc/approved-subnets -p tcp -dport 3389
IN ACCEPT -source +dc/approved-subnets -p icmp
EOF
}

# Gate 1: template exists and cluster is quorate
tcfg=$(timeout 15 qm config "$TEMPLATE")
grep -q '^template: 1' <<<"$tcfg" || { echo "VM $TEMPLATE is not a template"; exit 1; }
cstat=$(timeout 10 pvecm status)
grep -q 'Quorate:.*Yes' <<<"$cstat" || { echo "cluster not quorate"; exit 1; }

# Gate 2: every address must be unanswered before anything is created
for ip in "${IPS[@]}"; do
  arping -D -c 3 -w 4 -I vmbr0 "$ip" >/dev/null 2>&1 || { echo "$ip is in use, aborting"; exit 1; }
done

i=0
for ip in "${IPS[@]}"; do
  n=$((START + i))
  name="advcell-vm${n}"
  aff="${AFFINITY[$((n-1))]:?no affinity entry for VM $n}"
  vmid=$(timeout 15 pvesh get /cluster/nextid)
  pass=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-12)
  echo "== creating $name (vmid $vmid) at $ip"
  qm clone "$TEMPLATE" "$vmid" --name "$name" --full 1 --storage "$STORAGE"
  qm set "$vmid" --ciuser student --cipassword "$pass" \
     --ipconfig0 "ip=${ip}/24,gw=${GW}" --nameserver "$DNS" --affinity "$aff"
  write_fw "$vmid" "$ip"
  pve-firewall compile >/dev/null && echo "firewall OK for $vmid"
  echo "$name,$vmid,student,$pass,$ip" >> "$CRED"
  i=$((i+1))
  cstat=$(timeout 10 pvecm status)
  grep -q 'Quorate:.*Yes' <<<"$cstat" || { echo "quorum lost after $name, stopping"; exit 1; }
done
echo "done. credentials in $CRED"
