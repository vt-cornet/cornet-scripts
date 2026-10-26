# CORNET Proxmox Cluster Firewall Configuration

This directory maintains the declarative firewall rules and IPSETs deployed across the CORNET Proxmox cluster (`cornet-cluster`) and its guest virtual machines and containers.

## Architecture

Proxmox VE uses a three-tier hierarchical firewall engine (Datacenter/Cluster -> Host -> Guest):

```
+--------------------------------------------------------------+
|                Cluster Level (/etc/pve/firewall/cluster.fw)  |
|  - Default Incoming Policy: DROP                             |
|  - IPSET approved-subnets (Campus, Lab, VPN ranges)          |
|  - IPSET cluster-nodes (Corosync nodes)                      |
|  - Rules: Corosync (5405-5406/udp), SSH (22/tcp), GUI (8006) |
+------------------------------+-------------------------------+
                               |
            +------------------+------------------+
            |                                     |
            v                                     v
+-----------------------+             +-----------------------+
| LXC Containers        |             | QEMU Virtual Machines |
| - 200 (dns-server)    |             | - 100-103 (Compute)   |
| - 210 (pxe-server)    |             | - 299 (PXE test)      |
| - 220 (rustdesk)      |             | - 9040, 9099 (Golden) |
| - 230 (headscale)     |             +-----------------------+
+-----------------------+
```

---

## Files

| File | Scope | Purpose |
| :--- | :--- | :--- |
| [`cluster.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/cluster.fw) | Datacenter | Master cluster firewall, IPSET definitions, cluster-wide administrative access |
| [`guests/200.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/guests/200.fw) | LXC 200 | **DNS Server**: DNS (53 udp/tcp), DDNS API (5000/tcp), SSH (22/tcp) |
| [`guests/210.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/guests/210.fw) | LXC 210 | **PXE Server**: DHCP (67:68/udp open), TFTP (69/udp), HTTP (80/tcp), Status Logger (5001/tcp) |
| [`guests/220.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/guests/220.fw) | LXC 220 | **RustDesk Server**: NAT test (21115), hbbs/hbbr registration & relay (21116-21119) |
| [`guests/230.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/guests/230.fw) | LXC 230 | **Headscale VPN**: WireGuard tunnel (41641/udp), Control API (8080/tcp) |
| [`guests/299.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/guests/299.fw) | VM 299 | **PXE Securetest**: SSH (22/tcp), RDP (3389/tcp) |
| [`guests/100.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/guests/100.fw)–[`103.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/guests/103.fw) | VMs 100-103 | Research VMs: Anti-spoofing (IP & MAC filter), Isolated from cluster nodes, SSH + RDP from approved subnets |
| [`guests/9040.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/guests/9040.fw), [`guests/9099.fw`](file:///Users/pratheek/Projects/CodeBase%20Walkthroughs/cornet-scripts/firewall/guests/9099.fw) | VM Templates | Golden image templates with baseline network isolation |

---

## IPSET Definitions

### `approved-subnets`
Subnets authorized to access administrative interfaces (SSH, Web GUI) and guest management ports:
- `128.173.52.0/24`
- `128.173.88.0/21`
- `172.27.0.0/16`, `172.29.0.0/16`, `172.30.0.0/16`
- `198.82.18.128/26`
- `198.82.8.0/21` (Campus VPN Subnet)
- `45.3.120.0/22`, `45.3.124.0/23`, `45.3.126.0/23`

### `cluster-nodes`
Static internal cluster IPs permitted for Corosync synchronization:
- `198.82.18.154` (`cornet-node01`)
- `198.82.18.155` (`cornet-node02`)
- `128.173.88.72` (`cornet-node03`)
- `128.173.88.73` (`cornet-node04`)

---

## Synchronization and Deployment

Because Proxmox cluster configurations live in the distributed `/etc/pve/` filesystem (pmxcfs), modifying or restoring firewall rules on any single quorum node updates the entire cluster automatically:

```bash
# Push cluster configuration
scp firewall/cluster.fw root@198.82.18.154:/etc/pve/firewall/cluster.fw

# Push guest configuration (e.g. for container 200)
scp firewall/guests/200.fw root@198.82.18.154:/etc/pve/firewall/200.fw
```
