# Technical Deep-Dive: RHCOS Root Disk Expansion

## Overview

This document provides technical details about Red Hat Enterprise Linux CoreOS (RHCOS) storage architecture and why disk expansion requires multiple steps.

---

## RHCOS Storage Architecture

### What is RHCOS?

Red Hat Enterprise Linux CoreOS is a container-optimized OS specifically designed for OpenShift:

- **Immutable root filesystem:** `/sysroot` mounted read-only by default
- **OSTree-based updates:** Atomic, image-based system deployments
- **Ignition provisioning:** Initial configuration at first boot
- **Device mapper abstraction:** Additional layer between partition and filesystem

### Storage Stack Layers

```
┌─────────────────────────────────────────┐
│     XFS Filesystem (/sysroot)           │  ← What df -h shows
├─────────────────────────────────────────┤
│  Device Mapper: coreos-luks-root-nocrypt│  ← dm-0 device
├─────────────────────────────────────────┤
│     Partition (/dev/sdb4)               │  ← GPT partition
├─────────────────────────────────────────┤
│     Disk (/dev/sdb)                     │  ← VMDK in vSphere
└─────────────────────────────────────────┘
```

**Key Insight:** Each layer must be resized independently!

1. VMware extends VMDK
2. OS detects new disk size (rescan)
3. Partition table updated (growpart)
4. Device mapper resized (cryptsetup resize)
5. Filesystem expanded (xfs_growfs)

### Why Device Mapper Exists

The `coreos-luks-root-nocrypt` device mapper provides:

- **Encryption support:** Optional LUKS encryption for security
- **Flexibility:** LVM or other storage features without changing filesystem
- **Standardization:** Same interface regardless of underlying storage
- **Future-proofing:** Easy to add features (snapshots, thin provisioning)

**Important:** Despite the name "luks", this is NOT always real encryption:
- Some deployments: `dm-linear` device (simple passthrough)
- Others: Genuine LUKS2 encryption
- Name is standardized regardless

**Check your device type:**
```bash
cryptsetup status /dev/mapper/coreos-luks-root-nocrypt
```

Output:
- `type: LUKS2` or `type: LUKS1` → Real encryption
- `type: n/a` → dm-linear passthrough

---

## The Multi-Disk Reality

### Why Multiple Disks?

OpenShift nodes typically have 2-3 disks:

**Typical Setup:**
```
/dev/sda (32GB)  → Boot, data, or swap
/dev/sdb (120GB) → Root filesystem (/sysroot)
/dev/sdc (500GB) → Container storage (optional)
```

**Reasons for multiple disks:**
- Separate OS and data storage
- Performance optimization (different SCSI controllers)
- Storage tiering (SSD for OS, HDD for data)
- VMware template defaults

### Device Naming

**Disk naming depends on:**
1. SCSI controller order in vSphere
2. Boot order configuration
3. Historical VM template setup

**Common patterns:**
- `sda` = First SCSI disk on controller 0
- `sdb` = Second SCSI disk on controller 0
- `sdc` = First SCSI disk on controller 1

**Never assume!** Always verify with `lsblk | grep -B 10 sysroot`

---

## Why Reboot Appeared Necessary

### The Discovery Journey

**Initial belief:** Device mapper requires reboot to resize

**Reality:** We were working on the wrong disk!

### What Actually Happened

**Scenario:**
1. Node has `/dev/sda` (32GB) and `/dev/sdb` (120GB root)
2. Extended `/dev/sda` in vSphere by mistake
3. Ran all commands on `/dev/sda`
4. Root disk `/dev/sdb` unchanged
5. Device mapper has nothing to resize
6. Procedure "fails"
7. Reboot the node
8. Boot services check ALL disks
9. Root partition on `/dev/sdb` detected (correct size from manual vSphere extension)
10. Device mapper auto-created with correct size
11. **Reboot "fixed" it!**

**Wrong conclusion:** "Reboot is required"
**Right conclusion:** "We need to identify and use the correct disk"

### RHCOS Boot-Time Services

Services that run during boot and auto-resize:

**coreos-growpart.service:**
- Checks partition sizes at boot
- Automatically grows partitions if disk is larger
- Runs before filesystem mounts

**ignition-ostree-growfs.service:**
- Checks filesystem sizes at boot
- Automatically expands filesystems
- Runs after device mapper setup

**Why these services "saved" us:**
They detected the correct root partition size during boot and resized everything automatically, masking the fact that we had worked on the wrong disk!

---

## Device Mapper Deep-Dive

### What is Device Mapper?

Device Mapper (DM) is a kernel framework that provides:
- Virtual block devices on top of physical devices
- Mapping between logical and physical blocks
- Support for encryption, RAID, snapshots, etc.

### RHCOS Device Mapper Setup

**Check device mapper configuration:**
```bash
dmsetup table coreos-luks-root-nocrypt
```

**Output example:**
```
0 460322783 linear 8:20 32768
```

**Interpretation:**
- `0 460322783` = Start sector 0, size 460322783 sectors
- `linear` = Type (simple passthrough, despite "luks" name)
- `8:20` = Major:minor device number of backing device
- `32768` = Start offset on backing device

**Find backing device:**
```bash
ls -l /dev/sdb4
brw-rw---- 1 root disk 8, 20 Oct 30 /dev/sdb4
```

So `8:20` = `/dev/sdb4`

### Why cryptsetup resize Works

The `cryptsetup resize` command:

1. Reads current size of backing device (`/dev/sdb4`)
2. Updates device mapper table with new size
3. Activates new mapping
4. Filesystem can now expand

**Critical:** It must be run AFTER partition growth, otherwise:
- Reads old partition size
- No change to DM table
- Filesystem cannot expand

---

## LUKS Encryption Details

### Real LUKS vs dm-linear

**If your system has real LUKS encryption:**
```bash
$ cryptsetup status coreos-luks-root-nocrypt
/dev/mapper/coreos-luks-root-nocrypt is active and is in use.
  type:    LUKS2
  cipher:  aes-xts-plain64
  keysize: 512 bits
```

**Resize still works the same way:**
```bash
cryptsetup resize coreos-luks-root-nocrypt
```

**If dm-linear (no real encryption):**
```bash
$ cryptsetup status coreos-luks-root-nocrypt
/dev/mapper/coreos-luks-root-nocrypt is active.
  type: n/a
```

**Both use same resize command!**

### Why the Confusing Name?

Red Hat standardized on `coreos-luks-root-nocrypt` as the device mapper name regardless of whether LUKS encryption is actually enabled. This provides:
- Consistent naming across deployments
- Same scripts work for encrypted and non-encrypted
- Easy to enable encryption later

---

## Advanced Troubleshooting

### Partition Not Growing

**Issue:** `growpart` fails or shows "NOCHANGE"

**Possible causes:**
1. Working on wrong disk
2. Partition is not last partition on disk
3. GPT backup table corruption
4. Insufficient free space after partition

**Fix:**
```bash
# Verify disk size increased
fdisk -l /dev/sdb

# If disk still shows old size, rescan:
echo 1 > /sys/class/block/sdb/device/rescan

# If partition is not last on disk, cannot grow
# Use parted to check:
parted /dev/sdb print

# Fix GPT backup table:
parted /dev/sdb print
# Answer "Fix" when prompted
```

### Device Mapper Not Resizing

**Issue:** `cryptsetup resize` completes but DM device size unchanged

**Root cause:** Almost always wrong disk!

**Diagnosis:**
```bash
# 1. Check which device DM is using
dmsetup table coreos-luks-root-nocrypt
# Output: 0 250607583 linear 8:20 32768
#                              ^^^^
#                              major:minor

# 2. Find which device has this major:minor
ls -l /dev/sdb*
# Look for device with 8, 20

# 3. Check if THIS partition was grown
lsblk /dev/sdb4

# 4. If partition is still old size, you grew wrong partition!
```

### Filesystem Not Expanding

**Issue:** `xfs_growfs` shows no change

**Cause:** Device mapper not actually resized

**Fix:**
```bash
# Verify DM device size
lsblk | grep coreos-luks-root-nocrypt

# If still old size:
cryptsetup resize coreos-luks-root-nocrypt

# Then retry:
xfs_growfs /sysroot
```

### Multiple SCSI Controllers

**Issue:** Disk on different SCSI controller

**Identification:**
```bash
# List SCSI devices with controller info
lsscsi
```

**Output example:**
```
[0:0:0:0]    disk    VMware   Virtual disk     2.0   /dev/sda
[1:0:0:0]    disk    VMware   Virtual disk     2.0   /dev/sdb
[2:0:0:0]    disk    VMware   Virtual disk     2.0   /dev/sdc
```

Controller 0: `/dev/sda`
Controller 1: `/dev/sdb`
Controller 2: `/dev/sdc`

**Rescan specific controller:**
```bash
# Rescan controller 1
echo "- - -" > /sys/class/scsi_host/host1/scan
```

---

## Red Hat Official Position

### Support Status

From Red Hat knowledge base and support discussions:

> "Root disk expansion is not officially supported. The correct way is to rebuild a new node with the correct size."

**However:** Red Hat acknowledges this is sometimes necessary and provides workarounds in KB articles.

**KB Article 6970308:** Housekeeping /sysroot in OpenShift
- Discusses root filesystem management
- Provides guidance for disk expansion
- Recommends caution and testing

### Why Not Officially Supported?

1. **Cattle not Pets:** OpenShift nodes designed to be replaceable
2. **Machine API:** Should provision nodes with correct size
3. **ImmutableOS:** Root filesystem changes go against RHCOS design
4. **Risk:** Modifying root storage can cause boot issues

### When to Use Anyway

Acceptable scenarios:
- Legacy clusters without Machine API
- Bare metal installations
- Emergency capacity management
- Testing/development environments

**Always:**
- Test in non-production first
- Have backups/snapshots
- Plan for node replacement eventually

---

## Performance Considerations

### Online Operations

All operations in this procedure are **online** (no unmount needed):

**Partition growth:**
- `growpart` updates partition table
- Kernel re-reads partition table
- Mounted filesystems unaffected

**Device mapper resize:**
- `cryptsetup resize` updates DM mapping
- Active mappings remain active
- I/O continues uninterrupted

**Filesystem expansion:**
- `xfs_growfs` works on mounted XFS
- Background operation
- Performance impact minimal (< 5%)

### I/O Impact

**During expansion:**
- Filesystem metadata updates
- Allocation group creation
- B-tree restructuring

**Expected:**
- Slight increase in I/O wait
- May take 2-5 minutes for large expansions
- Pods continue running normally

**Monitoring:**
```bash
# Watch I/O during expansion
iostat -x 2 /dev/mapper/coreos-luks-root-nocrypt

# Check filesystem status
xfs_info /sysroot
```

---

## Comparison: Manual vs Reboot

### Manual Procedure (This Guide)

**Steps:** Rescan → Growpart → Cryptsetup → XFS Growfs
**Time:** 13-15 minutes
**Downtime:** Zero
**Risk:** Low (if correct disk used)
**Pros:**
- No pod disruption
- No drain/cordon needed
- Faster for single nodes

### Reboot Method

**Steps:** Rescan → Growpart → Drain → Reboot → Uncordon
**Time:** 25-50 minutes
**Downtime:** Node unavailable during reboot
**Risk:** Very low (RHCOS handles everything)
**Pros:**
- Boot services handle DM resize
- More "hands-off"
- Might catch other issues

### When to Use Each

**Manual (No Reboot):**
- Single node needing quick expansion
- Cluster at capacity (cannot drain safely)
- Testing/dev environments
- Confident in disk identification

**Reboot Method:**
- Multiple nodes (batch operations)
- Prefer automation
- Less confident in manual steps
- Want RHCOS to handle everything

---

## Version Compatibility

### OpenShift 4.16 (Validated)

- RHCOS kernel: 5.14+
- Device mapper: dm-crypt with LUKS2 support
- XFS: Version 5 with reflink support
- Tested and working

### Other Versions

**OpenShift 4.12-4.15:**
- Should work identically
- RHCOS storage stack consistent

**OpenShift 4.10-4.11:**
- Device mapper may differ
- Test in lab first

**OpenShift 3.x:**
- Uses RHEL, not RHCOS
- Different procedure required
- Not covered in this guide

### vSphere Versions

**Tested:**
- vSphere 7.x: Working
- vSphere 8.x: Working

**Requirements:**
- Hot-add disk support enabled
- SCSI controller supports rescan
- VM hardware version 14+

---

## Security Considerations

### LUKS Encryption

If your deployment uses real LUKS encryption:

**Key management:**
- Keys stored in `/etc/luks/keys/`
- Tang servers for network-bound encryption
- TPM-based unlocking (if configured)

**Resize does NOT require:**
- Re-entering passphrase
- Key rotation
- Re-encryption of data

**Data safety:**
- Expansion only adds new space
- Existing data untouched
- No re-encryption needed

### Audit Trail

**Commands to log:**
```bash
# Before
lsblk > /tmp/before-expansion.txt
df -h >> /tmp/before-expansion.txt

# After
lsblk > /tmp/after-expansion.txt
df -h >> /tmp/after-expansion.txt
```

**Include in change ticket:**
- Before/after disk sizes
- Commands executed
- Time of execution
- Node name and IP

---

## Automation Opportunities

### Ansible Playbook Example

```yaml
---
- name: Expand RHCOS root disk
  hosts: openshift_nodes
  become: yes
  tasks:
    - name: Identify root disk
      shell: lsblk | grep -B 10 sysroot | grep disk | awk '{print $1}'
      register: root_disk

    - name: Rescan SCSI bus
      shell: echo 1 > /sys/class/block/{{ root_disk.stdout }}/device/rescan

    - name: Grow partition
      command: growpart /dev/{{ root_disk.stdout }} 4
      ignore_errors: yes

    - name: Resize device mapper
      command: cryptsetup resize coreos-luks-root-nocrypt

    - name: Expand filesystem
      command: xfs_growfs /sysroot

    - name: Verify expansion
      shell: df -h /sysroot
      register: result

    - debug:
        var: result.stdout_lines
```

**Note:** Test thoroughly before production use!

### Validation Script

```bash
#!/bin/bash
# validate-disk-expansion.sh

echo "Checking disk expansion status..."

# Get root disk
ROOT_DISK=$(lsblk | grep -B 10 sysroot | grep disk | awk '{print $1}')
echo "Root disk: $ROOT_DISK"

# Check sizes
DISK_SIZE=$(lsblk -b /dev/$ROOT_DISK | tail -1 | awk '{print $4}')
PARTITION_SIZE=$(lsblk -b /dev/${ROOT_DISK}4 | tail -1 | awk '{print $4}')
DM_SIZE=$(lsblk -b /dev/mapper/coreos-luks-root-nocrypt | tail -1 | awk '{print $4}')
FS_SIZE=$(df -B1 /sysroot | tail -1 | awk '{print $2}')

echo "Disk size: $DISK_SIZE bytes"
echo "Partition size: $PARTITION_SIZE bytes"
echo "Device mapper size: $DM_SIZE bytes"
echo "Filesystem size: $FS_SIZE bytes"

# Validate proportions
if [ $((PARTITION_SIZE * 100 / DISK_SIZE)) -gt 95 ]; then
    echo "✓ Partition uses most of disk"
else
    echo "✗ Partition might not be fully expanded"
fi

if [ $((DM_SIZE * 100 / PARTITION_SIZE)) -gt 98 ]; then
    echo "✓ Device mapper uses partition fully"
else
    echo "✗ Device mapper might not be resized"
fi

if [ $((FS_SIZE * 100 / DM_SIZE)) -gt 95 ]; then
    echo "✓ Filesystem uses device mapper fully"
else
    echo "✗ Filesystem might not be expanded"
fi
```

---

## Key Learnings Summary

1. **Storage is multi-layered:** Disk → Partition → Device Mapper → Filesystem
2. **Each layer needs resizing:** Can't skip device mapper!
3. **Multi-disk is common:** Always verify which disk has /sysroot
4. **Reboot is optional:** Manual resize works when done correctly
5. **Wrong disk is #1 mistake:** Causes procedure to appear broken
6. **RHCOS is special:** Not standard RHEL, has device mapper abstraction
7. **Boot services are smart:** Auto-resize during boot can mask errors

---

**Document Version:** 1.0
**Last Updated:** 2025-01-30
**Tested On:** OpenShift 4.16, RHCOS, VMware vSphere 7.x/8.x
