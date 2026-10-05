# Issue #006: Extending OpenShift Node Root Disk (120GB → 220GB)

## Problem Statement

**Environment:**
- OpenShift Version: 4.16
- Infrastructure: VMware vSphere
- OS: Red Hat Enterprise Linux CoreOS (RHCOS)
- Component: Worker/Master node root disk

**Issue:**
Production OpenShift nodes running with 120GB root disk need expansion to 220GB due to increasing storage requirements from container images, logs, and system operations. Disk extended in vSphere but node OS not recognizing additional capacity.

**Impact:**
- Risk of disk space exhaustion (currently 80% usage)
- Potential pod evictions due to disk pressure
- Node could become NotReady if disk fills up
- Container image pulls may fail

---

## 🚨 CRITICAL: The Multi-Disk Challenge

**Most Common Mistake**: OpenShift nodes typically have **multiple disks**. You MUST identify which disk contains `/sysroot` before proceeding!

### Quick Disk Identification

```bash
# Method 1: Find root disk with lsblk (shows full tree)
lsblk

# Method 2: Direct check for /sysroot mount
df -h /sysroot | tail -1 | awk '{print $1}'

# Method 3: Find device from mount point
findmnt -n -o SOURCE /sysroot
```

**Example Output from `lsblk`:**
```
NAME                         MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda                            8:0    0    32G  0 disk              ← NOT root
sdb                            8:16   0   120G  0 disk              ← ROOT DISK!
├─sdb1                         8:17   0   384M  0 part /boot
└─sdb4                         8:20   0 119.5G  0 part
  └─coreos-luks-root-nocrypt 253:0    0 119.5G  0 dm   /sysroot    ← Root HERE!
```

**Identify the disk:** Look for the disk (sda, sdb, sdc) that contains the partition mounted at `/sysroot`

**Write down:**
- Root disk: `/dev/sdb` (YOUR DISK MAY BE DIFFERENT!)
- Root partition: `/dev/sdb4`
- Partition number: `4`

⚠️ **All commands in this procedure MUST use YOUR identified root disk!**

**Common Scenarios:**
- Scenario 1: `/dev/sda` = root, `/dev/sdb` = data
- Scenario 2: `/dev/sdb` = root, `/dev/sda` = data (common!)
- Scenario 3: `/dev/sdc` = root (multiple controllers)

---

## ✅ Solution: Production Procedure

**Timeline:** 10-15 minutes (no reboot) | 20-30 minutes (with reboot) | **Downtime:** Zero (no reboot) or 3-5 minutes (reboot)

💡 **Good News:** On many clusters, device mapper resize works **without reboot** using `cryptsetup resize`. Try the no-reboot method first. Reboot is only needed if `cryptsetup resize` doesn't expand the device mapper.

### Prerequisites Checklist

- [ ] Identified which disk contains /sysroot (Step 0 above)
- [ ] Disk extended in VMware vSphere console (120GB → 220GB)
- [ ] SSH access to target node confirmed
- [ ] Backup/snapshot verified
- [ ] Change ticket approved (if required)

### Step-by-Step Procedure

#### Step 0: Verify Current State

```bash
# SSH to node
ssh core@<node-name>

# Check current filesystem size
df -h /sysroot

# List block devices
lsblk

# Identify root disk (CRITICAL!)
lsblk | grep -B 10 sysroot
# Write down the disk device (sda, sdb, etc.)
```

**Expected Output:**
```
Filesystem                            Size  Used Avail Use% Mounted on
/dev/mapper/coreos-luks-root-nocrypt  120G   95G   25G  80% /sysroot
```

#### Step 1: Rescan SCSI Bus

After extending disk in vSphere, force OS to detect new size:

```bash
# ⚠️ Replace 'sdb' with YOUR root disk from Step 0!
echo 1 > /sys/class/block/sdb/device/rescan

# Verify disk now shows 220GB
fdisk -l /dev/sdb
```

**Expected Output:**
```
Disk /dev/sdb: 220 GiB, 236223201280 bytes, 461373440 sectors
```

If still showing 120GB:
- Verify vSphere extension completed
- Double-check you're using the CORRECT disk
- Try: `for host in /sys/class/scsi_host/host*/scan; do echo "- - -" > $host; done`

#### Step 2: Extend Partition

```bash
# ⚠️ Use YOUR root disk and partition number!
growpart /dev/sdb 4

# Verify partition extended
lsblk
```

**Expected Output:**
```
CHANGED: partition=4 start=1050624 old: size=250607583 new: size=460322783
```

**Verification with lsblk:**
```
NAME MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sdb    8:16   0   220G  0 disk
└─sdb4 8:20   0 219.5G  0 part              ← Partition now 219.5G
  └─coreos-luks-root-nocrypt
     253:0    0 119.5G  0 dm   /sysroot    ← DM still 119.5G (expected)
```

**Note:** You may see GPT warning - this is normal and auto-corrected.

#### Step 3: Resize Device Mapper

RHCOS uses device mapper abstraction. There are two methods to resize - try Method A first, use Method B (reboot) if needed.

##### Method A: Online Resize (No Reboot - Works on Many Clusters)

```bash
# Try to resize device mapper
cryptsetup resize coreos-luks-root-nocrypt

# Check if it worked
lsblk
```

**If device mapper shows 219.5G:** ✓ Success! Skip to Step 5 (Expand Filesystem)

**If you get read-only filesystem error when running xfs_growfs:**
```
xfs_growfs: XFS_IOC_FSGROWFSDATA xfsctl failed: Read-only file system
```

**Fix with mount namespace isolation:**
```bash
# Create isolated mount namespace
unshare --mount

# Become root
sudo su

# Remount /sysroot as read-write
mount -o remount,rw /sysroot

# Now expand the filesystem
xfs_growfs /sysroot

# Verify
df -h /sysroot
```

**If device mapper still shows 119.5G after cryptsetup resize:** Proceed to Method B (Reboot)

##### Method B: Reboot (Required When Online Resize Fails)

If Method A doesn't work, proceed to Step 4 (Reboot). This is normal behavior in some production RHCOS environments. The device mapper will auto-resize during reboot.

#### Step 4: Reboot Node (Required for Device Mapper Resize)

Since partition is already expanded to 219.5G, reboot will trigger RHCOS boot services to auto-resize the device mapper.

**Complete Node Reboot Procedure:**

```bash
# 1. Check node status
oc get nodes -o wide

# 2. Cordon node (prevent new pods from scheduling)
oc adm cordon node/<node-name>

# 3. Drain node (move workloads safely to other nodes)
oc adm drain node/<node-name> --ignore-daemonsets --delete-emptydir-data --disable-eviction --force

# 4. Wait for drain to complete
oc get pods -A -o wide | grep <node-name>
```

**Reboot the node - Choose Method A or B:**

**Method A: Using SSH (if available)**
```bash
ssh core@<node-name>
sudo systemctl reboot
```

**Method B: Using oc debug (no SSH needed)**
```bash
# Open debug session on the node
oc debug node/<node-name>

# Once inside the debug pod, chroot to host filesystem
chroot /host

# Reboot the node
systemctl reboot
```

**Wait for node to come back:**

```bash
# From workstation, watch node status
oc get nodes -w
```

Wait until node shows **Ready** (typically 3-5 minutes).

**Verify device mapper auto-resized:**

```bash
# SSH back to node
ssh core@<node-name>

# Check device mapper size
lsblk
```

**Expected Output:**
```
sdb    8:16   0   220G  0 disk
└─sdb4 8:20   0 219.5G  0 part
  └─coreos-luks-root-nocrypt
     253:0    0 219.5G  0 dm   /sysroot    ← DM now 219.5G ✓
```

#### Step 5: Expand XFS Filesystem

After device mapper is resized (now shows 219.5G):

```bash
# Expand filesystem to use full DM device size
sudo xfs_growfs /sysroot

# Verify final size
df -h /sysroot
```

**Expected Output:**
```
Filesystem                            Size  Used Avail Use% Mounted on
/dev/mapper/coreos-luks-root-nocrypt  220G   95G  125G  44% /sysroot
```

#### Step 6: Uncordon Node

**From workstation/bastion:**

```bash
# Make node schedulable again
oc adm uncordon <node-name>

# Verify pods scheduling back
oc get pods -A -o wide | grep <node-name>
```

#### Step 7: Final Verification

```bash
# Check complete stack
lsblk

# Verify no errors
dmesg | tail -20

# Check from OpenShift
oc get nodes
oc describe node <node-name> | grep -i disk
```

**Success Criteria:**
- Disk: 220G ✓
- Partition: 219.5G ✓
- Device mapper: 219.5G ✓
- Filesystem: 220G ✓
- Node: Ready and schedulable ✓
- No errors in dmesg ✓

---

## ⚡ Quick Reference Commands

### Complete Command Sequence (Without Reboot - Try First)

**On Node (via SSH or oc debug)**
```bash
# 0. IDENTIFY ROOT DISK (CRITICAL!)
lsblk
# Note: Root disk = /dev/??? (look for disk with /sysroot)

# 1. Rescan disk (use YOUR root disk!)
echo 1 > /sys/class/block/sdb/device/rescan
fdisk -l /dev/sdb

# 2. Grow partition
growpart /dev/sdb 4
lsblk

# 3. Resize device mapper
cryptsetup resize coreos-luks-root-nocrypt
lsblk

# 4. If xfs_growfs fails with read-only error, use mount namespace:
unshare --mount
sudo su
mount -o remount,rw /sysroot
xfs_growfs /sysroot

# 5. Verify
df -h /sysroot
```

**If device mapper doesn't resize (still shows old size), use reboot method below.**

---

### Complete Command Sequence (With Reboot - If Above Fails)

**Part 1: On Node (via SSH or oc debug)**
```bash
# 0. IDENTIFY ROOT DISK (CRITICAL!)
lsblk
# Note: Root disk = /dev/??? (look for disk with /sysroot)

# 1. Rescan disk (use YOUR root disk!)
echo 1 > /sys/class/block/sdb/device/rescan
fdisk -l /dev/sdb

# 2. Grow partition
growpart /dev/sdb 4
lsblk

# 3. Try device mapper resize (may not work)
cryptsetup resize coreos-luks-root-nocrypt
lsblk
```

**Part 2: From Workstation (Reboot Procedure)**
```bash
# 1. Check node status
oc get nodes -o wide

# 2. Cordon node
oc adm cordon node/<node-name>

# 3. Drain node
oc adm drain node/<node-name> --ignore-daemonsets --delete-emptydir-data --disable-eviction --force

# 4a. Reboot via SSH (if available)
ssh core@<node-name> sudo systemctl reboot

# 4b. OR Reboot via oc debug (no SSH needed)
oc debug node/<node-name>
# Inside debug pod: chroot /host && systemctl reboot

# 5. Wait for node Ready
oc get nodes -w
```

**Part 3: After Reboot (On Node)**
```bash
# Verify device mapper resized
lsblk  # Should show DM at 219.5G

# Expand filesystem
sudo xfs_growfs /sysroot

# Verify
df -h /sysroot
```

**Part 4: From Workstation (Finish)**
```bash
# Uncordon node
oc adm uncordon node/<node-name>

# Verify pods scheduling back
oc get pods -A -o wide | grep <node-name>
```

**Timeline:**
- Partition expansion: 3-5 min
- Cordon + Drain: 5-10 min
- Reboot: 3-5 min
- Filesystem expansion: 2-3 min
- **Total: 20-30 minutes | Downtime: 3-5 min (reboot only)**

---

## 🔄 Node Reboot Methods Explained

### Method A: Using SSH (Traditional)

**When to use:**
- SSH access is available to nodes
- You prefer direct shell access
- Simpler and faster

**Prerequisites:**
- SSH enabled on nodes
- SSH key or credentials configured
- Network connectivity to node

**Procedure:**
```bash
# From workstation
ssh core@<node-name>

# On node
sudo systemctl reboot
```

**Pros:**
- ✅ Direct access
- ✅ Faster
- ✅ Can run multiple commands

**Cons:**
- ❌ Requires SSH access
- ❌ May not work in restricted environments

---

### Method B: Using oc debug (OpenShift Native)

**When to use:**
- SSH is not available or disabled
- Restricted network environment
- Corporate security policies block SSH
- Prefer OpenShift-native tools

**Prerequisites:**
- `oc` CLI configured
- Cluster admin or appropriate RBAC permissions
- Ability to create debug pods

**Procedure:**
```bash
# From workstation
oc debug node/<node-name>

# Once inside the debug pod
chroot /host

# Now you're in the node's filesystem
systemctl reboot
```

**How it works:**
1. `oc debug node/<node-name>` creates a privileged pod on the target node
2. Pod has access to host filesystem via `/host`
3. `chroot /host` changes root to node's filesystem
4. You can now run node commands as if SSH'd

**Pros:**
- ✅ No SSH needed
- ✅ Works in restricted environments
- ✅ Uses OpenShift RBAC
- ✅ Audit trail via OpenShift

**Cons:**
- ❌ Slightly more complex
- ❌ Requires pod creation permissions

---

### Complete Reboot Workflow (Both Methods)

**Step 1: Prepare node**
```bash
oc get nodes -o wide
oc adm cordon node/<node-name>
oc adm drain node/<node-name> --ignore-daemonsets --delete-emptydir-data --disable-eviction --force
```

**Step 2: Choose your reboot method**

**Option A (SSH):**
```bash
ssh core@<node-name>
sudo systemctl reboot
```

**Option B (oc debug):**
```bash
oc debug node/<node-name>
chroot /host
systemctl reboot
```

**Step 3: Wait and verify**
```bash
oc get nodes -w  # Wait for Ready status (3-5 min)
```

**Step 4: Finish up**
```bash
oc adm uncordon node/<node-name>
oc get pods -A -o wide | grep <node-name>
```

---

## ⚠️ Troubleshooting

### Issue: Device mapper doesn't resize

**Root Cause:** Most likely working on wrong disk!

**Fix:**
```bash
# 1. Verify which disk has /sysroot
lsblk | grep -B 10 sysroot

# 2. Check if you used this disk in all commands
# If not, restart procedure with correct disk!
```

### Issue: Disk rescan doesn't detect new size

**Fix:**
```bash
# Rescan all SCSI hosts
for host in /sys/class/scsi_host/host*/scan; do
    echo "- - -" > $host
done

# Verify
fdisk -l /dev/sdb
```

### Issue: xfs_growfs shows no change

**Cause:** Device mapper not resized

**Fix:**
```bash
# Check DM device size
lsblk | grep coreos-luks-root-nocrypt

# If still old size, run:
cryptsetup resize coreos-luks-root-nocrypt

# Then retry:
xfs_growfs /sysroot
```

### Issue: xfs_growfs fails with "Read-only file system"

**Error:**
```
xfs_growfs: XFS_IOC_FSGROWFSDATA xfsctl failed: Read-only file system
```

**Cause:** The `/sysroot` filesystem is mounted read-only

**Fix:**
```bash
# Create isolated mount namespace to avoid affecting system
unshare --mount

# Become root
sudo su

# Remount /sysroot as read-write
mount -o remount,rw /sysroot

# Now expand the filesystem
xfs_growfs /sysroot

# Verify expansion
df -h /sysroot
```

**Note:** This method has been validated on multiple production clusters and avoids the need for a reboot in many cases.

### Issue: Nothing works!

**First Action - STOP and verify:**
```bash
lsblk | grep -B 10 sysroot
```

**Check:**
1. Which disk shows `/sysroot`?
2. Did you extend THIS disk in vSphere?
3. Did all your commands use THIS disk?

**Common mistake:**
```bash
# Wrong: Root is on sdb but you ran commands on sda
echo 1 > /sys/class/block/sda/device/rescan  ❌
growpart /dev/sda 4  ❌

# Right: Use the disk with /sysroot
echo 1 > /sys/class/block/sdb/device/rescan  ✓
growpart /dev/sdb 4  ✓
```

---

## 📝 Real Command Logs Example

### Step 0: Identify Root Disk
```
$ lsblk | grep -B 10 sysroot
NAME MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda    8:0    0    32G  0 disk
sdb    8:16   0   120G  0 disk
├─sdb1 8:17   0   384M  0 part /boot
└─sdb4 8:20   0 119.5G  0 part
  └─coreos-luks-root-nocrypt
     253:0    0 119.5G  0 dm   /sysroot

CONCLUSION: Root disk = /dev/sdb
```

### Step 1: After Rescan
```
$ echo 1 > /sys/class/block/sdb/device/rescan
$ fdisk -l /dev/sdb
Disk /dev/sdb: 220 GiB, 236223201280 bytes, 461373440 sectors
```

### Step 2: After Growpart
```
$ growpart /dev/sdb 4
CHANGED: partition=4 start=1050624 old: size=250607583 new: size=460322783

$ lsblk
sdb    8:16   0   220G  0 disk
└─sdb4 8:20   0 219.5G  0 part
  └─coreos-luks-root-nocrypt
     253:0    0 119.5G  0 dm    ← Still 119.5G (DM not resized yet)
```

### Step 3: After Cryptsetup Resize Attempt
```
$ cryptsetup resize coreos-luks-root-nocrypt
$ lsblk
sdb    8:16   0   220G  0 disk
└─sdb4 8:20   0 219.5G  0 part
  └─coreos-luks-root-nocrypt
     253:0    0 119.5G  0 dm    ← Still 119.5G (typical in production)
```

**Note:** Device mapper often doesn't resize with `cryptsetup` in production RHCOS. This is expected behavior - proceed with reboot.

### Step 4: After Reboot
```
$ lsblk
sdb    8:16   0   220G  0 disk
└─sdb4 8:20   0 219.5G  0 part
  └─coreos-luks-root-nocrypt
     253:0    0 219.5G  0 dm    ← Auto-resized during boot ✓
```

### Step 5: After XFS Grow
```
$ xfs_growfs /sysroot
data blocks changed from 31325696 to 57540352

$ df -h /sysroot
Filesystem                            Size  Used Avail Use% Mounted on
/dev/mapper/coreos-luks-root-nocrypt  220G   95G  125G  44% /sysroot
```

---

## 🔒 Safety Notes

### Production-Safe Operations

✅ **Safe commands:**
- `echo 1 > /sys/class/block/*/device/rescan` - Detects new disk size
- `growpart` - Only extends partition table
- `xfs_growfs` - Online filesystem expansion (cannot shrink)
- `oc adm cordon/drain/uncordon` - Proper OpenShift node maintenance

✅ **Reboot required for:**
- Device mapper resize in production RHCOS environments
- Proper workload migration with cordon/drain before reboot

❌ **NEVER run these commands:**
- `dmsetup suspend` on root filesystem - **FREEZES NODE COMPLETELY**
- `dmsetup reload` - Requires suspend (dangerous)
- `systemctl stop` on critical services
- Force operations on mounted filesystems

### Why Reboot Is Typically Required

**Production RHCOS behavior:**
1. Partition expands successfully with `growpart`
2. `cryptsetup resize` typically **does not work** on dm-linear devices in production
3. Device mapper resize requires reboot to take effect
4. Boot services (`coreos-growpart.service`, `ignition-ostree-growfs.service`) automatically detect partition size changes
5. Device mapper auto-resizes to match partition during boot process

**Rare exception:**
If `cryptsetup resize` works (some non-production or specific RHCOS configurations), reboot can be skipped. However, in most production environments, reboot is required.

---

## 🎯 Key Takeaways

### Critical Success Factors

1. **Identify root disk FIRST** - Use `lsblk` to see full disk tree
2. **Multi-disk awareness** - Never assume `/dev/sda` is root
3. **Correct disk usage** - All commands must use the same disk
4. **Device mapper layer** - Requires reboot in production RHCOS
5. **Proper node maintenance** - Use cordon/drain before reboot

### Common Multi-Disk Scenarios

**Scenario A: sdb = root (Your case)**
```
sda (32GB)  → Data or swap disk
sdb (120GB) → Root filesystem ← Expand this!
```

**Scenario B: sda = root**
```
sda (120GB) → Root filesystem ← Expand this!
sdb (500GB) → Container storage
```

### Time Estimates

- **Without reboot (preferred):** 10-15 minutes, zero downtime
- **With reboot (if needed):** 20-30 minutes, 3-5 minutes downtime
- **Multiple nodes:** Can do in parallel if no reboot needed; one at a time if reboot required

### Prevention

- Monitor disk usage with Prometheus/Dynatrace
- Set alerts at 70% for proactive expansion
- Document node disk configurations
- Maintain capacity planning spreadsheet

---

## 📚 Related Information

- **Technical deep-dive:** See `TECHNICAL-DETAILS.md` for RHCOS architecture, device mapper details, and advanced troubleshooting
- **RHCOS Version:** 4.16 (validated)
- **vSphere:** Hot-add disk expansion supported
- **Filesystem:** XFS (standard for RHCOS root)

---

## 📊 Summary

**Problem:** Node root disk at 80% capacity, extended to 220GB in vSphere but OS not recognizing

**Root Cause:** Multi-layer storage stack (disk → partition → device mapper → filesystem) requires each layer to be resized independently

**Solution:** 7-step procedure with minimal downtime:
1. Identify root disk (CRITICAL!)
2. Rescan SCSI bus
3. Grow partition
4. Reboot node (with cordon/drain)
5. Verify device mapper auto-resized
6. Expand filesystem
7. Uncordon node

**Critical Discovery:**
1. The #1 mistake is working on the wrong disk - always use `lsblk` to identify which disk contains `/sysroot`
2. Device mapper resize **often works without reboot** using `cryptsetup resize` - try this first
3. If `xfs_growfs` fails with read-only error, use `unshare --mount` + `mount -o remount,rw /sysroot` to fix
4. Reboot is only needed when `cryptsetup resize` doesn't expand the device mapper

**Result:** Root disk successfully expanded from 120GB to 220GB.
- **Without reboot:** Zero downtime, 10-15 minutes
- **With reboot (if needed):** 3-5 minutes downtime, 20-30 minutes total

---

**Last Updated:** 2025-01-28
**Validated On:** OpenShift 4.16, RHCOS, VMware vSphere (Multiple Production Clusters)
