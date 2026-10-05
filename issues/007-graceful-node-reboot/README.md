# Issue #007: How to Reboot OpenShift Node Gracefully

## Problem Statement

**Environment:**
- OpenShift Version: 4.14+ (applies to all versions)
- Infrastructure: Any (vSphere, Bare Metal, AWS, Azure, etc.)
- Component: Worker/Master nodes
- When needed: Maintenance, kernel updates, hardware changes, troubleshooting

**Issue:**
Need to reboot OpenShift nodes for maintenance or troubleshooting without causing service disruptions or pod failures. Improper node reboots can cause:
- Workload interruptions
- Pod eviction failures
- Data loss from local storage
- Service downtime

**Impact:**
- Rebooting nodes without proper procedure can disrupt running applications
- Pods may not migrate gracefully to other nodes
- StatefulSets and applications with local storage can lose data
- Cluster instability if multiple nodes rebooted simultaneously

---

## ✅ Solution: Graceful Node Reboot Procedure

**Timeline:** 5-15 minutes per node | **Downtime:** 2-5 minutes (node only)

### Prerequisites

- [ ] `oc` CLI configured with cluster admin or appropriate permissions
- [ ] Cluster has sufficient capacity to handle workloads from rebooted node
- [ ] Change ticket approved (if required)
- [ ] Choose reboot method: SSH or oc debug

---

## 🔄 Two Methods to Reboot OpenShift Nodes

### Method A: Using SSH (Traditional)

**Best for:**
- Direct node access available
- Simple and fast execution
- You have SSH keys configured

**Requirements:**
- SSH access enabled to nodes
- SSH key or credentials
- Network connectivity to node

### Method B: Using oc debug (OpenShift Native)

**Best for:**
- SSH is disabled or restricted
- Corporate security policies
- Centralized audit trail
- Prefer OpenShift RBAC

**Requirements:**
- Cluster admin or node debug permissions
- `oc` CLI access
- Ability to create privileged pods

---

## 📋 Complete Graceful Reboot Procedure

### Step 1: Check Node Status

```bash
# View all nodes and their status
oc get nodes -o wide

# Check node details
oc describe node <node-name>

# Check pods running on the node
oc get pods -A -o wide --field-selector spec.nodeName=<node-name>
```

**What to check:**
- Node is `Ready`
- No critical system pods (if possible)
- Workload distribution across cluster

---

### Step 2: Cordon the Node

**Purpose:** Prevent new pods from being scheduled on the node

```bash
# Cordon the node (mark as unschedulable)
oc adm cordon node/<node-name>

# Verify node is cordoned
oc get nodes
```

**Expected output:**
```
NAME          STATUS                     ROLES    AGE   VERSION
worker1       Ready,SchedulingDisabled   worker   30d   v1.27.6+f67aeb3
```

Note the `SchedulingDisabled` status.

---

### Step 3: Drain the Node

**Purpose:** Gracefully move pods to other nodes before reboot

```bash
# Drain the node (evict all pods)
oc adm drain node/<node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --disable-eviction \
  --force

# Alternative: Without disabling eviction (safer but may fail)
oc adm drain node/<node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data
```

**Flag explanations:**
- `--ignore-daemonsets`: Don't fail if DaemonSet pods exist (they'll restart automatically)
- `--delete-emptydir-data`: Delete pods using emptyDir volumes
- `--disable-eviction`: Skip eviction API, directly delete pods (faster but less safe)
- `--force`: Force deletion of pods not managed by controllers

**Wait for drain to complete:**
```bash
# Check if any pods remain
oc get pods -A -o wide --field-selector spec.nodeName=<node-name>

# Should show only DaemonSet pods or none
```

**Typical drain time:** 2-10 minutes depending on pod count and grace periods

---

### Step 4: Reboot the Node

Choose **Method A (SSH)** or **Method B (oc debug)**:

#### Method A: Using SSH

```bash
# Connect to node via SSH
ssh core@<node-name>

# Reboot the node
sudo systemctl reboot
```

The SSH connection will drop after reboot is initiated.

#### Method B: Using oc debug

```bash
# Create debug pod on the node
oc debug node/<node-name>

# Once inside the debug pod, you'll see a prompt like:
# sh-4.4#

# Change root to host filesystem
chroot /host

# Reboot the node
systemctl reboot
```

**How oc debug works:**
1. Creates a privileged pod on the target node
2. Pod mounts host filesystem at `/host`
3. `chroot /host` switches to node's root filesystem
4. You can now run node commands as if SSH'd

**Exit the debug pod:**
The pod will automatically terminate when node reboots.

---

### Step 5: Wait for Node to Come Back

```bash
# Watch node status (updates every 2 seconds)
oc get nodes -w

# Or check periodically
watch -n 5 oc get nodes
```

**Expected sequence:**
1. Node shows `NotReady` (1-2 minutes)
2. Node shows `Ready,SchedulingDisabled` (2-4 minutes)

**Typical reboot time:** 3-5 minutes

**If node takes longer than 10 minutes:**
- Check node console in infrastructure (vSphere, BMC, cloud console)
- Verify network connectivity
- Check DHCP/DNS if applicable
- Review node logs after it comes back

---

### Step 6: Verify Node Health

```bash
# Check node is Ready
oc get nodes

# Check node details
oc describe node <node-name>

# Verify no errors
oc get events --field-selector involvedObject.name=<node-name> --sort-by='.lastTimestamp'

# Check system pods on the node
oc get pods -n openshift-* -o wide --field-selector spec.nodeName=<node-name>
```

**Health checks:**
- ✅ Status: `Ready,SchedulingDisabled`
- ✅ No disk/memory/PID pressure
- ✅ System pods running
- ✅ No recent error events

---

### Step 7: Uncordon the Node

**Purpose:** Allow pods to be scheduled on the node again

```bash
# Uncordon the node (mark as schedulable)
oc adm uncordon node/<node-name>

# Verify node is schedulable
oc get nodes
```

**Expected output:**
```
NAME          STATUS   ROLES    AGE   VERSION
worker1       Ready    worker   30d   v1.27.6+f67aeb3
```

Note: `SchedulingDisabled` is removed.

---

### Step 8: Verify Workload Distribution

```bash
# Check pods on the node
oc get pods -A -o wide --field-selector spec.nodeName=<node-name>

# Check overall pod distribution
oc get pods -A -o wide | grep <node-name>

# Verify no pending pods
oc get pods -A --field-selector status.phase=Pending
```

**What to verify:**
- Pods are scheduling back to the node
- No pods stuck in `Pending` or `CrashLoopBackOff`
- Workload distributed evenly across cluster

---

## ⚡ Quick Reference Commands

### Complete Workflow (SSH Method)

```bash
# Step 1: Check status
oc get nodes -o wide
oc get pods -A -o wide --field-selector spec.nodeName=<node-name>

# Step 2: Cordon
oc adm cordon node/<node-name>

# Step 3: Drain
oc adm drain node/<node-name> --ignore-daemonsets --delete-emptydir-data --disable-eviction --force

# Step 4: Reboot via SSH
ssh core@<node-name> sudo systemctl reboot

# Step 5: Wait for Ready
oc get nodes -w

# Step 6: Verify health
oc describe node <node-name>

# Step 7: Uncordon
oc adm uncordon node/<node-name>

# Step 8: Verify workloads
oc get pods -A -o wide --field-selector spec.nodeName=<node-name>
```

---

### Complete Workflow (oc debug Method)

```bash
# Step 1: Check status
oc get nodes -o wide

# Step 2: Cordon
oc adm cordon node/<node-name>

# Step 3: Drain
oc adm drain node/<node-name> --ignore-daemonsets --delete-emptydir-data --disable-eviction --force

# Step 4: Reboot via oc debug
oc debug node/<node-name>
# Inside debug pod:
chroot /host
systemctl reboot

# Step 5: Wait for Ready
oc get nodes -w

# Step 6: Verify health
oc describe node <node-name>

# Step 7: Uncordon
oc adm uncordon node/<node-name>

# Step 8: Verify workloads
oc get pods -A -o wide --field-selector spec.nodeName=<node-name>
```

---

## ⚠️ Troubleshooting

### Issue: Drain hangs or takes very long

**Cause:** Pods have long termination grace periods or PodDisruptionBudgets

**Fix:**
```bash
# Check which pods are stuck
oc get pods -A -o wide --field-selector spec.nodeName=<node-name>

# Check PodDisruptionBudgets
oc get pdb -A

# Force drain with shorter timeout
oc adm drain node/<node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --grace-period=30

# Or skip eviction entirely (more aggressive)
oc adm drain node/<node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --disable-eviction \
  --force
```

---

### Issue: Node stuck in NotReady after reboot

**Cause:** Node not coming back online, network issues, or service failures

**Fix:**
```bash
# Check node status from infrastructure
# - vSphere: Check VM console
# - Bare metal: Check BMC/iLO console
# - Cloud: Check instance console logs

# If node is up but NotReady, SSH to node
ssh core@<node-name>

# Check critical services
sudo systemctl status kubelet
sudo systemctl status crio

# Check node logs
sudo journalctl -u kubelet -n 100
sudo journalctl -u crio -n 100

# Restart services if needed
sudo systemctl restart kubelet
sudo systemctl restart crio
```

---

### Issue: oc debug fails with permission errors

**Cause:** Insufficient RBAC permissions

**Fix:**
```bash
# Check your permissions
oc auth can-i create pods/exec

# Request cluster-admin or specific permissions
# - nodes/debug
# - pods/exec
# - pods/create in privileged namespace

# Alternative: Use SSH method instead
ssh core@<node-name>
```

---

### Issue: Drain fails due to local storage

**Cause:** Pods using local emptyDir or hostPath volumes

**Fix:**
```bash
# Identify pods with local storage
oc get pods -A -o json --field-selector spec.nodeName=<node-name> | \
  jq '.items[] | select(.spec.volumes[]? | select(.emptyDir or .hostPath))'

# Option 1: Delete emptyDir data (data will be lost)
oc adm drain node/<node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force

# Option 2: Manually backup and delete pods
oc delete pod <pod-name> -n <namespace>
```

---

### Issue: Cannot uncordon node

**Cause:** Node has taints or RBAC issues

**Fix:**
```bash
# Check node taints
oc describe node <node-name> | grep -A 5 Taints

# Remove node-unschedulable taint if present
oc adm uncordon node/<node-name>

# Or manually remove taint
oc adm taint nodes <node-name> node.kubernetes.io/unschedulable:NoSchedule-
```

---

## 🔐 Best Practices

### 1. One Node at a Time

❌ **Never reboot multiple nodes simultaneously**
```bash
# DON'T DO THIS:
for node in worker1 worker2 worker3; do
  oc adm cordon node/$node
  oc adm drain node/$node --force
done
```

✅ **Reboot one node, verify, then proceed to next**
```bash
# DO THIS:
oc adm cordon node/worker1
oc adm drain node/worker1 --ignore-daemonsets --delete-emptydir-data --force
# ... reboot worker1 ...
# ... wait for Ready ...
oc adm uncordon node/worker1
# Verify everything is healthy, then proceed to worker2
```

---

### 2. Check Cluster Capacity

Before draining, ensure cluster can handle the workload:

```bash
# Check cluster resource usage
oc adm top nodes

# Check pod distribution
oc get pods -A -o wide | awk '{print $8}' | sort | uniq -c

# Ensure sufficient capacity on other nodes
```

**Recommended:** Keep at least 30% capacity buffer for failover.

---

### 3. Respect Maintenance Windows

- Schedule reboots during low-traffic periods
- Notify stakeholders before maintenance
- Have rollback plan ready
- Keep monitoring active during procedure

---

### 4. Master Node Reboots

**⚠️ Special considerations for master nodes:**

- **Never reboot all masters simultaneously**
- Reboot one master at a time
- Wait for etcd quorum before next reboot
- Verify cluster operators healthy

```bash
# Check etcd health
oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="EtcdMembersAvailable")]}{.message}{"\n"}{end}'

# Check cluster operators
oc get co

# Proceed only if all operators Available=True
```

**Recommended master reboot sequence:**
1. Reboot master1, wait 5 minutes
2. Verify etcd quorum and cluster operators
3. Reboot master2, wait 5 minutes
4. Verify again
5. Reboot master3

---

### 5. StatefulSet Considerations

**StatefulSets require special care:**

```bash
# Check StatefulSets on the node
oc get statefulsets -A -o wide

# Ensure StatefulSet has replicas > 1
oc get statefulset <name> -n <namespace> -o jsonpath='{.spec.replicas}'

# Wait for StatefulSet pods to be Running on other nodes before uncordoning
oc get pods -n <namespace> -l app=<statefulset-app>
```

---

### 6. Monitoring During Reboot

**Monitor these during node reboot:**

```bash
# Watch node status
watch -n 2 oc get nodes

# Monitor cluster operators
watch -n 5 'oc get co | grep -v "True.*False.*False"'

# Check for pending pods
watch -n 5 'oc get pods -A --field-selector status.phase=Pending'

# Monitor events
oc get events -A --watch
```

---

## 📝 Real Command Log Example

### Scenario: Rebooting worker8 for disk expansion

```bash
$ oc get nodes -o wide
NAME      STATUS   ROLES    AGE   VERSION
worker8   Ready    worker   45d   v1.27.6+f67aeb3

$ oc adm cordon node/worker8
node/worker8 cordoned

$ oc get nodes
NAME      STATUS                     ROLES    AGE   VERSION
worker8   Ready,SchedulingDisabled   worker   45d   v1.27.6+f67aeb3

$ oc adm drain node/worker8 --ignore-daemonsets --delete-emptydir-data --disable-eviction --force
node/worker8 already cordoned
WARNING: ignoring DaemonSet-managed Pods: openshift-dns/dns-default-abcde, openshift-monitoring/node-exporter-xyz
evicting pod example-app/webapp-12345
evicting pod example-app/worker-67890
pod/webapp-12345 evicted
pod/worker-67890 evicted
node/worker8 drained

$ oc get pods -A -o wide --field-selector spec.nodeName=worker8
NAMESPACE          NAME                    READY   STATUS    NODE
openshift-dns      dns-default-abcde       2/2     Running   worker8
openshift-monitoring node-exporter-xyz     1/1     Running   worker8

$ oc debug node/worker8
Starting pod/worker8-debug ...
To use host binaries, run `chroot /host`
sh-4.4# chroot /host
sh-5.1# systemctl reboot
Connection to worker8 closed by remote host.

$ oc get nodes -w
NAME      STATUS                     ROLES    AGE   VERSION
worker8   Ready,SchedulingDisabled   worker   45d   v1.27.6+f67aeb3
worker8   NotReady,SchedulingDisabled worker  45d   v1.27.6+f67aeb3
worker8   NotReady,SchedulingDisabled worker  45d   v1.27.6+f67aeb3
worker8   Ready,SchedulingDisabled    worker  45d   v1.27.6+f67aeb3

$ oc describe node worker8 | grep -A 5 Conditions
Conditions:
  Type             Status  LastHeartbeatTime                 LastTransitionTime
  ----             ------  -----------------                 ------------------
  MemoryPressure   False   Mon, 04 Nov 2024 13:45:22 +0300   Thu, 19 Sep 2024 10:15:30 +0300
  DiskPressure     False   Mon, 04 Nov 2024 13:45:22 +0300   Thu, 19 Sep 2024 10:15:30 +0300
  PIDPressure      False   Mon, 04 Nov 2024 13:45:22 +0300   Thu, 19 Sep 2024 10:15:30 +0300
  Ready            True    Mon, 04 Nov 2024 13:45:22 +0300   Mon, 04 Nov 2024 13:43:10 +0300

$ oc adm uncordon node/worker8
node/worker8 uncordoned

$ oc get nodes
NAME      STATUS   ROLES    AGE   VERSION
worker8   Ready    worker   45d   v1.27.6+f67aeb3

$ oc get pods -A -o wide --field-selector spec.nodeName=worker8
NAMESPACE          NAME                    READY   STATUS    NODE
openshift-dns      dns-default-abcde       2/2     Running   worker8
openshift-monitoring node-exporter-xyz     1/1     Running   worker8
example-app        webapp-54321            1/1     Running   worker8

SUCCESS: Node rebooted gracefully in 5 minutes
```

---

## 🎯 Key Takeaways

### Critical Success Factors

1. **Always use cordon → drain → reboot → uncordon sequence**
2. **Never skip the drain step** - Causes ungraceful pod terminations
3. **Wait for drain to complete** - Don't reboot until pods are evacuated
4. **One node at a time** - Never reboot multiple nodes simultaneously
5. **Verify node health** - Check before uncordoning
6. **Monitor workloads** - Ensure pods reschedule properly

### Time Estimates

- **Worker node**: 5-15 minutes total
  - Drain: 2-5 minutes
  - Reboot: 3-5 minutes
  - Verification: 2-5 minutes

- **Master node**: 10-20 minutes total
  - More careful verification needed
  - Check etcd quorum
  - Verify cluster operators

### Common Use Cases

- **Kernel updates**: Requires reboot to load new kernel
- **Hardware changes**: Memory, disk, network card changes
- **Troubleshooting**: Resolve node-level issues
- **Maintenance**: Apply OS patches or configuration changes
- **Disk expansion**: After storage operations (see Issue #006)

---

## 📚 Related Information

- **Issue #006**: Extending OpenShift Node Root Disk (reboot procedure context)
- **Official Docs**: [Red Hat OpenShift Node Management](https://docs.redhat.com/en/documentation/openshift_container_platform/4.14/html/nodes/working-with-nodes#nodes-nodes-rebooting)
- **Technical Details**: See `TECHNICAL-DETAILS.md` for understanding drain behavior, eviction API, and PodDisruptionBudgets

---

## 📊 Summary

**Problem:** Need to reboot OpenShift nodes for maintenance without disrupting workloads

**Solution:** 8-step graceful reboot procedure using cordon → drain → reboot → uncordon workflow

**Two Methods:**
1. **SSH Method**: Direct SSH access to node (`ssh core@<node> && sudo systemctl reboot`)
2. **oc debug Method**: OpenShift-native approach (`oc debug node/<node>`, then `chroot /host && systemctl reboot`)

**Critical Steps:**
1. Cordon (prevent new pods)
2. Drain (move existing pods)
3. Reboot (via SSH or oc debug)
4. Verify health (check node Ready)
5. Uncordon (allow scheduling)

**Result:** Node rebooted gracefully with minimal service impact. Typical time: 5-15 minutes per node with 2-5 minutes downtime.

---

**Last Updated:** 2025-01-31
**Validated On:** OpenShift 4.14+, Production Environments
**Production Tested:** Multiple environments (vSphere, bare metal)
