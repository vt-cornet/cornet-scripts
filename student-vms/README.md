# Student / Course VMs (golden template + clones)

Build and operations guide for the per-student KVM VMs used in the *Advanced Cellular* hands-on session
(OAI, FlexRIC, xApp development). Students who cannot run Ubuntu 24.04/26.04 or WSL2 on their own laptop
(for example, Apple-silicon Macs) get one of these VMs and connect over the VT VPN with SSH or RDP.

The workflow is: build one **golden VM**, seal it, convert it to a **template**, then **clone** one VM per
student. Everything below was built and validated on `cornet-node04` on 2026-10-12/13.

> **Status when this was written (fill in / verify before committing):**
> golden template `9040` built and sealed; `advcell-vm1` (VM 100) fully validated; `advcell-vm2` (VM 101)
> required a re-clone after an interrupted copy (see Troubleshooting); `advcell-vm3` (VM 102) was the spare.
> Results for VM 101/102 were not captured in the source notes: `[ ]` confirm.

---

## 1. Design summary

| Item | Choice | Why |
|---|---|---|
| Guest type | KVM VM (not LXC) | OAI/FlexRIC need a full Ubuntu kernel and SCTP; LXC is the default only for general student workloads |
| OS | Ubuntu 26.04 cloud image (24.04 is the fallback) | Matches the supported-OS list given to students |
| Size | 16 vCPU (8 physical cores + SMT siblings), 16 GB RAM, 150 GB thin disk, 8 GB swapfile | OAI in RFsim mode is not real-time; RAM can run out during a parallel build, hence swap and `-j8` |
| CPU | `--cpu host --sockets 1 --cores 16 --numa 1 --balloon 0`, `--affinity` per VM | Real 8-core/16-thread guests, one socket per VM, no ballooning |
| Storage | `local-zfs` on node04 (ZFS, thin) | Clones stay on node04; no HA, no migration |
| Network | `vmbr0`, **static IP** in the node's campus /24, set via cloud-init | See 4.1: DHCP gave unregistered MACs a private, VPN-unreachable range |
| Isolation | Per-VM Proxmox firewall: `macfilter`, `ipfilter`, node block, VPN-only SSH/RDP | VMs share `vmbr0` with the nodes, so the VM firewall is the only isolation |
| Remote access | SSH (password) + GNOME Remote Desktop (system-level RDP, needs GDM) | Same stack as the lab workstations |
| Naming | Template `advcell-golden-2604` (ID 9040); clones `advcell-vm1..N` (IDs 100+); safety copy ID 9099 | Distinguishable per student |
| Secrets | Generated per clone, written to a root-only CSV, never in the template or the repo | No hard-coded secrets |

### CPU pinning table (node04)

SMT siblings on node04 are `n` and `n+96` (verified for CPUs 4, 36, 43; all on socket 0). Cores 0-3 and
44-47 are left for the host. Socket 1 stays free.

| VM | `--affinity` |
|---|---|
| golden build / advcell-vm1 | `4-11,100-107` |
| advcell-vm2 | `12-19,108-115` |
| advcell-vm3 | `20-27,116-123` |
| advcell-vm4 | `28-35,124-131` |
| advcell-vm5 | `36-43,132-139` |

Re-verify with `cat /sys/devices/system/cpu/cpu<N>/topology/thread_siblings_list` on any other node before reusing the table.

### Address plan (node04 campus /24, gateway `.1`)

`.210` golden VM, `.211` advcell-vm1, `.212` advcell-vm2, `.213` spare, `.214` spare.
No addresses are formally allocated to CORNET for VMs. These were chosen by sweeping the whole /24
with ARP and picking a gap away from live hosts (`.205`-`.216` was empty). **They are not reserved**; ask
campus IT to reserve or exclude them from DHCP.

---

## 2. Rules for working on a cluster with no quorum margin

When this was built the cluster was quorate with exactly the minimum votes (3 of 3 active; the fourth node
was deliberately out). Therefore:

- Run the **quorum gate** before every step that writes to `/etc/pve` (VM create/clone/set, firewall files):
  ```bash
  timeout 10 pvecm status | grep -E 'Nodes:|Quorate'     # expect the right node count and Quorate: Yes
  journalctl -u corosync --since "5 min ago" --no-pager | grep -c 'new membership'   # expect 0
  ```
- Never stop or restart `corosync` on an active node. Never reboot or do maintenance on an active node.
- If a `qm`/`pvesh` command hangs: check `pvecm status` first and do not retry blindly. Processes stuck in `D`
  state mean `pmxcfs` is wedged; the fix is restarting `pve-cluster` on **that node only**.
  Ctrl+C will not kill a `D`-state process. Close the terminal, or in OpenSSH press Enter, `~`, `.`.
- Use only `timeout`-wrapped, read-only diagnostics that avoid `/etc/pve` while diagnosing.
- All VM work stays on node04's storage; nothing may depend on the out-of-cluster node.

---

## 3. Build procedure

Run on `cornet-node04` as root unless noted. Substitute your storage name (`local-zfs` here).

### 3.1 Pre-flight (read-only)

```bash
timeout 10 pvecm status | grep -E 'Nodes:|Quorate'
lscpu -e=CPU,CORE,SOCKET,NODE | head -60
for c in 4 36 43; do echo -n "cpu$c: "; cat /sys/devices/system/cpu/cpu$c/topology/thread_siblings_list; done
free -h; zpool list; zfs list; pvesm status; qm list; pct list
pve-firewall status
cat /etc/pve/firewall/cluster.fw          # confirm the +dc/cluster-nodes and +dc/approved-subnets IP sets exist
qm status 9040                            # "does not exist" = ID is free
```

### 3.2 Choose addresses

```bash
# Live hosts in the /24 (about 15 s). Pick a block far from dense runs of live addresses.
seq 2 254 | xargs -P 32 -I{} sh -c 'arping -D -c 2 -w 2 -I vmbr0 128.173.88.{} >/dev/null 2>&1 || echo {}' | sort -n | tr '\n' ' '; echo
# Recheck the chosen ones right before use (all must say no-reply)
for ip in 210 211 212 213 214; do
  arping -D -c 3 -w 4 -I vmbr0 128.173.88.$ip >/dev/null 2>&1 && echo "$ip no-reply" || echo "$ip IN-USE"
done
```

An empty ARP reply proves only that nothing answers *now*. A powered-off host or a future DHCP lease can still collide.

### 3.3 Create the golden VM

```bash
cd /tmp
wget https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img
wget https://cloud-images.ubuntu.com/resolute/current/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing          # must print OK
# For the 24.04 fallback replace "resolute" with "noble" in both URLs.

qm create 9040 --name advcell-golden-2604 --ostype l26 --cpu host --sockets 1 --cores 16 \
  --memory 16384 --balloon 0 --numa 1 --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,firewall=1 --agent enabled=1 --serial0 socket --vga std \
  --affinity 4-11,100-107
qm disk import 9040 resolute-server-cloudimg-amd64.img local-zfs
qm set 9040 --scsi0 local-zfs:vm-9040-disk-0,discard=on,iothread=1,ssd=1
qm disk resize 9040 scsi0 150G
qm set 9040 --ide2 local-zfs:cloudinit --boot order=scsi0

BUILDPW=$(openssl rand -base64 12 | tr -d '/+=')
qm set 9040 --ciuser build --cipassword "$BUILDPW"
echo "build password (golden VM only): $BUILDPW"       # copy it now; Proxmox stores it hashed
```

Write the VM firewall **before the first start** (see section 5) and give it a static address:

```bash
write_fw 9040 128.173.88.210                           # function in student-vm.fw.template
pve-firewall compile >/dev/null && echo FW-OK
qm set 9040 --ipconfig0 ip=128.173.88.210/24,gw=128.173.88.1 --nameserver <campus-dns-ip>
qm start 9040
```

Log in on the console (`qm terminal 9040`, exit with Ctrl+O) or the GUI console as `build`. The
**QEMU guest agent is not in the cloud image**, so `qm guest ...` fails until it is installed (3.4).

### 3.4 Inside the golden VM

Install a terminal multiplexer first; the desktop install is long:

```bash
sudo apt-get update && sudo apt-get install -y tmux && tmux new -s build
```

**Packages and desktop**

```bash
sudo apt-get install -y ubuntu-desktop-minimal gnome-remote-desktop qemu-guest-agent openssh-server openssl
sudo systemctl enable --now qemu-guest-agent
sudo systemctl set-default graphical.target
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo mkdir -p /etc/skel/.config && echo yes | sudo tee /etc/skel/.config/gnome-initial-setup-done
```

Installer prompts: choose **gdm3** as the display manager (system-level RDP needs GDM, not lightdm), answer **No** to
`kdump-tools` (it reserves RAM via `crashkernel=` for no benefit), keep the local version of any config-file prompt.
If kdump was enabled anyway: `sudo apt-get purge -y kdump-tools && sudo update-grub`, then confirm
`systemctl is-enabled kdump-tools` says `not-found` and `/proc/cmdline` has no `crashkernel=`.

**Keep systemd-networkd as the network renderer (required)**

Installing the desktop adds `/usr/lib/netplan/00-network-manager-all.yaml` (`renderer: NetworkManager`). netplan then stops writing
a networkd `.network` file, networkd falls back to the initramfs catch-all (`zzzz-dracut-default.network`, `DHCP=yes`), and the VM
boots onto a private DHCP lease instead of its static address. Override the renderer with a later-sorting file:

```bash
sudo mkdir -p /root/netplan-bak && sudo cp -a /etc/netplan/. /root/netplan-bak/
sudo install -m 600 99-renderer-networkd.yaml /etc/netplan/99-renderer-networkd.yaml   # file in this directory
sudo netplan get | head -4          # must show: renderer: networkd
sudo netplan generate
ls /run/systemd/network/            # must now include 10-netplan-eth0.network
sudo netplan apply
```

Do **not** disable NetworkManager and do **not** touch the `/usr/lib` file. Reboot and confirm only the static address is present
(`ip -br a`, `networkctl status eth0 | grep 'Network File'`). Keep this override file in the template; cloud-init regenerates only
`50-cloud-init.yaml` per clone.

**SSH and swap**

```bash
sudo tee /etc/ssh/sshd_config.d/10-students.conf <<'EOF'
PasswordAuthentication yes
PermitRootLogin no
EOF
sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin'      # yes / no
sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
swapon --show
```

Password SSH is acceptable here only because the per-VM firewall limits port 22 to the approved subnets. Root login stays off;
students use `sudo`.

**Per-VM RDP first-boot service**

Each clone must generate its own TLS key so no two VMs share one. Install the two files from this directory:

```bash
sudo install -m 755 grd-firstboot.sh /usr/local/sbin/grd-firstboot.sh
sudo install -m 644 grd-firstboot.service /etc/systemd/system/grd-firstboot.service
sudo systemctl daemon-reload
sudo systemctl enable grd-firstboot.service
systemd-analyze verify /etc/systemd/system/grd-firstboot.service && echo UNIT-OK
```

Notes that cost time:

- `grdctl --system ...` needs **root**. Without `sudo` over SSH it falls back to polkit and fails with `No session for cookie`.
- Order the unit `After=cloud-init.service`. `After=cloud-final.service` creates an ordering cycle with `multi-user.target`
  and systemd silently deletes the job.
- The script must use `systemctl start --no-block` (it runs during boot).
- The unit is a one-shot with no `RemainAfterExit`, so a successful run shows `inactive (dead)` with `status=0/SUCCESS`.
- `ConditionPathExists=!/var/lib/gnome-remote-desktop/rdp.key`: a leftover key in the template stops the service from running on
  clones, so every clone would share the template's key. Clean up before sealing (3.5).
- The VM has no TPM, so GRD stores the credential in a plain GKeyFile under `/var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop/credentials.ini`.
  Root-only, but it must not be baked into the template.

See also `remote-desktop/README.md` (GDM requirement, certificate ownership by the `gnome-remote-desktop` user, macOS Windows App fix).

### 3.5 Test, clean up, seal

Test once on the golden VM (optional but recommended):

```bash
sudo reboot
sudo systemctl status grd-firstboot.service --no-pager | head -8     # status=0/SUCCESS
sudo grdctl --system status                                          # RDP enabled, cert/key paths present
ss -tlnp | grep 3389
sudo grdctl --system rdp set-credentials student <temp-test-password>
# connect with an RDP client; log in as the build user (the student account does not exist on the golden VM)
```

**Cleanup is mandatory and must be the last thing before shutdown (no reboot after it, because a reboot regenerates the key):**

```bash
sudo systemctl stop gnome-remote-desktop.service
sudo grdctl --system rdp clear-credentials
sudo grdctl --system rdp disable
sudo rm -f /var/lib/gnome-remote-desktop/rdp.crt /var/lib/gnome-remote-desktop/rdp.key
sudo rm -f /var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop/credentials.ini
sudo find /var/lib/gnome-remote-desktop -type f          # must print nothing
```

Pre-seal checklist:

```bash
hostname                                       # advcell-golden-2604
systemctl get-default                          # graphical.target
systemctl is-active qemu-guest-agent           # active
systemctl is-enabled grd-firstboot.service     # enabled
sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin'   # yes / no
swapon --show                                  # 8G /swapfile
ls /etc/skel/.config/gnome-initial-setup-done
ls /etc/netplan/                               # 50-cloud-init.yaml and 99-renderer-networkd.yaml
systemctl is-enabled kdump-tools 2>&1          # not-found
```

Seal:

```bash
sudo passwd -l build
sudo rm -f /etc/netplan/50-cloud-init.yaml     # holds the golden VM's static address; cloud-init regenerates it per clone
sudo apt-get clean
sudo journalctl --rotate && sudo journalctl --vacuum-time=1s
sudo fstrim -av
cat /dev/null > ~/.bash_history; history -c
sudo cloud-init clean --logs
sudo truncate -s 0 /etc/machine-id
sudo shutdown -h now
```

Do not boot the golden VM again; booting regenerates identity and undoes the seal. Keep `99-renderer-networkd.yaml`.

### 3.6 Templatize (on node04)

```bash
qm status 9040                                        # wait for: stopped
timeout 10 pvecm status | grep -E 'Nodes:|Quorate'
qm set 9040 --delete affinity                         # clones must not inherit the build pin
qm template 9040
qm config 9040 | grep -E '^(template|name|affinity)'  # template: 1, name set, no affinity
```

**Do not take a snapshot before templating.** `qm template` fails with "VM contains snapshots". For a rollback copy, make a **full
clone** *after* templating and never boot it:

```bash
qm clone 9040 9099 --name advcell-golden-2604-bak --full 1 --storage local-zfs
```

---

## 4. Network and firewall details

### 4.1 Why static addresses

A first boot on DHCP gave the golden VM a private `10.4.4.0/24` lease from `10.4.4.1`, apparently for an unregistered MAC. That range was
**not reachable from the VT VPN**. A static address in the node's own campus /24 (set in cloud-init) was reachable. The reason VT hands out
the private range was not confirmed. Static addressing also removes the need for DDNS per VM.

Consequence: the addresses must come from a block nobody else uses (see the address plan) and should be reserved by campus IT.

### 4.2 Per-VM firewall (`student-vm.fw.template`)

Each VM gets `/etc/pve/firewall/<vmid>.fw`. Clones do **not** inherit the template's file, so the clone script writes one per VM.
The files as deployed are tracked in `firewall/guests/` (`9040.fw`, `100.fw`-`103.fw`) and match `student-vm.fw.template` apart from the address.

- `macfilter: 1` and `ipfilter: 1` with `[IPSET ipfilter-net0]` listing only the VM's address (anti-spoofing).
- `dhcp: 1` stays so boot-time DHCP discovery is permitted.
- `IN DROP` and `OUT DROP` for `+dc/cluster-nodes` come **first**. The datacenter `approved-subnets` set contains the /21 that holds
  the nodes, so without the node block a student VM would match the SSH/RDP allow rules and could reach the nodes.
- Then `IN ACCEPT` SSH (22), RDP (3389) and ICMP from `+dc/approved-subnets` only.
- Do **not** edit `cluster.fw` for this. It is live host protection (`policy_in: DROP`); a mistake on a cluster with no quorum margin
  is the wrong risk, and rollback of a per-VM file is just deleting it.
- Known limits: VM-to-VM traffic inside the same approved range is not blocked, and `cluster-nodes` must list every node, lab PC
  and server the VMs must not reach.
- IPv6: guests still show a SLAAC address. With `ipfilter: 1`, outbound IPv6 failed in testing (`ping -6` failed), which is the safe result.

Validate with `pve-firewall compile >/dev/null && echo OK` before powering on a VM. Roll back with `rm /etc/pve/firewall/<vmid>.fw`.

### 4.3 DNS caveat

Campus DNS (the resolver the VMs use) does **not** resolve `*.cornet.wireless.vt.edu`; those names only resolve via the CORNET dnsmasq
server. Student VMs are therefore handed out by **IP**. If you want names, add static A records on the CORNET dnsmasq server and tell students to use
a resolver that can see it, or finish the campus DNS delegation.

---

## 5. Cloning

Script: `clone-advcell.sh` (parameterized as `START=<n> clone-advcell.sh <ip> [<ip>...]`). It:

1. gates on the template existing and the cluster being quorate;
2. refuses to start if any target address answers ARP;
3. for each address: picks the next free VM ID, generates a random password, full-clones from template `9040`, sets cloud-init user
   `student`, the static IP, DNS and CPU affinity, writes the per-VM firewall, appends `name,vmid,user,password,ip` to a root-only CSV
   (`/root/oai-vm-credentials.csv`, `umask 077`), and re-checks quorum.

`START` fixes the name: `START=2` makes the first VM `advcell-vm2` and pins it to the second affinity slot.

Install and run:

```bash
install -m 700 clone-advcell.sh /root/clone-advcell.sh
bash -n /root/clone-advcell.sh && echo SYNTAX-OK
timeout 10 pvecm status | grep -E 'Nodes:|Quorate'
arping -D -c 3 -w 4 -I vmbr0 128.173.88.211; echo "exit: $?"     # 0 = nobody answered
setsid nohup env START=1 /root/clone-advcell.sh 128.173.88.211 > /root/clone-vm1.log 2>&1 < /dev/null &
sleep 2; tail -f /root/clone-vm1.log          # Ctrl+C stops only tail; wait for "done. credentials in ..."
```

Run **detached with `setsid nohup`**, one VM at a time. A plain SSH session or tmux-less shell that dies mid-copy kills `qemu-img`
(first attempt: `interrupted by signal` at 23 %). Proxmox removes the partial VM and disk, so recovery is just rerunning the same
command. A full clone of 150 GB takes about 5 minutes. Do not run two clones at once: both would pick the same `nextid`.

The container the script runs in must define `write_fw` (it is embedded in the script).

---

## 6. Post-clone validation (per VM)

Set the variables, then run the sections in order. Do the first clone completely before cloning the rest.

```bash
VMID=100; IP=128.173.88.211; NAME=advcell-vm1
```

**Gate and clone check**

```bash
timeout 10 pvecm status | grep -E 'Nodes:|Quorate'
qm config $VMID | grep -E 'name|ipconfig0|affinity'
cat /etc/pve/firewall/$VMID.fw
tail -1 /root/oai-vm-credentials.csv | cut -d, -f1,2,3,5        # never print the password column
```

**Start and wait for the agent**

```bash
qm start $VMID
until qm agent $VMID ping 2>/dev/null; do sleep 5; done; echo agent-up
```

**Network and identity**

```bash
qm guest exec $VMID -- ip -br a                                   # only $IP/24; no 10.4.4.x
qm guest exec $VMID -- hostname                                   # $NAME
qm guest exec $VMID -- bash -c 'wc -c < /etc/machine-id'          # 33, not 0
qm guest exec $VMID -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub   # must differ from every other VM
qm guest exec $VMID -- sudo -u student sudo -n true               # "exitcode" : 0
qm guest exec $VMID -- bash -c 'nc -vz -w3 <node04-ip> 22; echo exit:$?'   # must FAIL (node block)
arping -c 20 -I vmbr0 $IP | grep -oE "from [0-9.]+ \[[0-9A-Fa-f:]+\]" | sort | uniq -c   # one MAC
```

`qm guest exec` prints JSON and does not stream; read the `"exitcode"` field. `&& echo OK` tests the host command, not the guest's.
If the IP is `10.4.4.x`, check `ls /etc/netplan/; netplan get | head -4` (renderer override missing).

**RDP credential, login name and service restart (required)**

```bash
pw=$(awk -F, -v id=$VMID '$2==id{print $4}' /root/oai-vm-credentials.csv)
qm guest exec $VMID -- grdctl --system rdp set-credentials student "$pw"
qm guest exec $VMID -- usermod -c "Student" student
qm guest exec $VMID -- systemctl restart gnome-remote-desktop.service
qm guest exec $VMID -- grdctl --system status
```

`status` should show RDP `enabled`, `Username: (hidden)` and a TLS fingerprint different from the template's and from every other clone's.
The password is briefly visible in `ps` on the node (admins only). If a student later runs `passwd`, the RDP credential keeps the old
password; tell them.

The restart matters: with the credentials set while the service was running, the Windows App on macOS failed with error `0x204`
("couldn't connect to the remote PC") and worked after re-setting the credentials and restarting the service. The exact cause was not isolated.
`0x204` is also the symptom of the known FreeRDP 3.32+ regression with the macOS Windows App documented in `remote-desktop/README.md`;
the golden VM did **not** have `remote-desktop/fix-gnome-rdp.sh` applied, so check which `libfreerdp` version it ships (section 7).

**Why `usermod -c "Student"`:** GDM's login tile shows the account's full name, and cloud images name the default user "Ubuntu", so students saw
an "Ubuntu" tile for the `student` account. (An optional cloud-init `gecos` setting was proposed but not tested; `usermod` is deterministic.)

**From a laptop on the VPN**

```bash
ping -c 3 $IP
ssh student@$IP
```

then RDP to `$IP` as `student` with the CSV password.

---

## 7. Handing VMs to students

- Send each student the **IP, username `student` and password privately** (Teams/email). Never post credentials on Canvas.
- Tell them SSH is the dependable path; RDP is for GUI use. Suggested wording:
  > Connect with `ssh student@<ip>` while on VT VPN. For a desktop, use the Windows App with `student` and your password.
  > If it hangs at "securing connection," cancel and retry, or use SSH.
- Students still need a laptop to reach the VM. They have `sudo`, so OAI/FlexRIC installs in class work.
- OAI and FlexRIC are **not** in the template; students install them in class (the golden VM has only the OS, desktop and remote access).
- Record which student has which VM.

### Known issue: Mac RDP hangs at "securing connection"

Connecting from macOS (Microsoft Windows App) to both lab Ubuntu PCs and these VMs is intermittent: it hangs at "securing connection".
Cause not diagnosed. Candidates, in test order:

0. **The FreeRDP 3.32+ regression already documented in `remote-desktop/README.md`** (TLS handshake / protocol negotiation failure with the
   Microsoft client, error `0x204`/`0x104`). `remote-desktop/fix-gnome-rdp.sh` rolls `libfreerdp*`/`libwinpr*` back (24.04: `3.31.0+dfsg-0ubuntu0.24.04.1`,
   26.04: `3.24.2+dfsg-1ubuntu1`) and pins them with `apt-mark hold`. It was not applied to the golden VM. `[ ]` Check the installed version
   (`dpkg -l | grep libfreerdp`); if it is 3.32 or newer, apply the script in the golden VM (before the cleanup and seal in 3.5), then re-test from a Mac.
   The fix targets an instant failure, whereas the hang is intermittent, so it may not explain the hang.
1. Stalled TLS/NLA handshake over the VPN path (test large-packet loss: `ping -D -s 1472 -c 5 <ip>`; a smaller RSA-2048 certificate in
   `grd-firstboot.sh` would shrink the handshake, but that means un-templating and re-sealing).
2. A stale saved credential/entry in the client: create a fresh entry, set credentials to ask each time, username exactly `student`.
3. GDM not ready right after boot: retry after a minute.
4. The known Windows App redirection incompatibility documented for the lab workstations (`use redirection server name:i:1` in the exported `.rdp`
   profile; see `remote-desktop/README.md`). `[ ]` not yet tested against these VMs.
5. FreeRDP-based clients (Thincast, Homebrew `freerdp`) avoid the Microsoft client entirely and are a good A/B test.

---

## 8. Teardown (after class)

```bash
qm stop <vmid> && qm destroy <vmid> --purge && rm -f /etc/pve/firewall/<vmid>.fw     # per clone
shred -u /root/oai-vm-credentials.csv                                                  # when passwords are no longer needed
qm destroy 9099 --purge                                                                # safety copy, once clones proved out
```

Keep the template. Tell campus IT which addresses were used so they can be reserved or released.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `qm`/`pvesh` hangs; Ctrl+C does nothing | `pmxcfs` wedged or quorum lost (process in `D` state) | Open a new SSH session, run the cluster checks in section 2, restart `pve-cluster` on that node only if D-state processes are stuck |
| `QEMU guest agent is not running` right after first boot | Cloud image ships without the agent | Install `qemu-guest-agent` in the VM (console login); include it in the template |
| Golden VM came up on `10.4.4.x` after installing the desktop | netplan renderer switched to NetworkManager | `99-renderer-networkd.yaml` (section 3.4); do not disable NetworkManager |
| SSH to the VM times out from VPN | VM firewall allow list, private range, or wrong address | Compare the laptop's address with `approved-subnets`; check `ip -br a` in the guest via console |
| `grd-firstboot.service` did not run: "Found ordering cycle" | `After=cloud-final.service` | Use `After=cloud-init.service` (section 3.4) |
| `grdctl --system ...` as normal user: `No session for cookie` | Needs root | Use `sudo` |
| `qm template` fails: "VM contains snapshots" | Snapshot taken before templating | `qm delsnapshot 9040 <name>`, then template; take a full clone instead of a snapshot |
| Clone fails: `qemu-img ... interrupted by signal` | SSH session dropped | Rerun with `setsid nohup`; partial VM is cleaned up automatically |
| Windows App `0x204` | Credentials set while GRD was running (cause not isolated), or the FreeRDP 3.32+ regression | Re-set credentials, restart `gnome-remote-desktop`; if it persists run `remote-desktop/fix-gnome-rdp.sh` |
| `kdump-tools` enabled after desktop install | Installer default | Purge it, `update-grub`, verify no `crashkernel=` |
| Login tile says "Ubuntu" | Default user's full name | `usermod -c "Student" student` |
| Clone shares the template's RDP key | `rdp.key` left in the template | Clean up before sealing (section 3.5); re-seal if needed |

---

## 10. Recovery

- **Bad clone:** `qm stop <id>; qm destroy <id> --purge; rm -f /etc/pve/firewall/<id>.fw`; delete its CSV line; rerun the clone.
- **Bad template:** destroy and rebuild from the cloud image (all steps above are scripted), or promote the safety copy
  (`qm template 9099`, then clone from it).
- **Bad firewall file:** `rm /etc/pve/firewall/<id>.fw`. For a lockout the Proxmox GUI/`qm terminal` console still works.
- **Lost build password:** `qm set 9040 --cipassword "$(openssl rand -base64 12 | tr -d '/+=')"`, print it, then stop and start the VM.
  If that fails, rebuild.

---

## 11. Related incident: duplicate IP caused corosync flapping (2026-10-12)

Documented here because it affects whether it is safe to build VMs.

- Symptom: `qm`/`pvesh` hung; corosync membership flapped every 15-25 s, splitting nodes by subnet (two votes each, no quorum).
  `corosync-cfgtool` still showed every link `connected`, so this was not a clean link-down.
- Root cause: a campus device was answering ARP for the static IP of `node03`, so traffic went to whichever device answered last.
  The other device was not ours (all NICs, BMCs and guest configs were ruled out).
- Mitigation: `corosync` was stopped on node03 only (it holds no guests); the cluster ran quorate on the remaining three.
  `pmxcfs` on node04 had wedged and was fixed by restarting `pve-cluster` there.
- Open: needs campus IT to find the other device and reserve/exclude the address. Do not bring node03 back until
  `arping -c 40 -I vmbr0 <node03-ip>` shows a single MAC, then watch membership for 15 minutes.
- Permanent fix for corosync stability remains the private `vmbr1` network over a WireGuard overlay.

Useful read-only diagnostics: `corosync-quorumtool -s`, `corosync-cfgtool -s`, `pvecm status`, the `journalctl -u corosync` grep in section 2.

---

## 12. Open items

- [ ] Reserve/exclude the VM address block with campus IT.
- [ ] Decide whether to keep password SSH or move to keys for non-technical students.
- [ ] Decide whether to pre-install OAI/FlexRIC build prerequisites in the template (currently installed in class).
- [ ] Test the cloud-init `gecos` setting, the `gnome-initial-setup-done` first-login marker and `ipfilter` against IPv6 on a clone.
- [ ] Diagnose the macOS "securing connection" hang (section 7).
- [ ] Add names for the VMs to the CORNET DNS server and/or finish campus DNS delegation (section 4.3).
- [ ] Merge the `grd-firstboot` per-VM key path (`/var/lib/gnome-remote-desktop`) with the workstation script's (`/etc/gnome-remote-desktop`), or document why they differ.
- [ ] Decide whether the template should include the `remote-desktop/fix-gnome-rdp.sh` FreeRDP rollback (section 7, candidate 0).
