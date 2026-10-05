# How to Force OpenShift to NOT Use restricted-v2 SCC

## Current Situation
Pod is using `restricted-v2` SCC and you want to use a custom SCC instead.

---

## Method 1: Remove restricted-v2 Access (Not Recommended)

⚠️ **Warning:** This affects ALL pods using this service account in the namespace.

```bash
# Check what SCCs the service account currently has
oc describe sa merchant-portal-icashpro -n nmp-web-preprod

# Remove restricted-v2 access from service account
# Note: restricted-v2 is granted by default to all authenticated users
# You need to override this at namespace level

# Create a role that explicitly denies restricted-v2 (this doesn't actually work in OpenShift)
# OpenShift doesn't support SCC denial, only grants
```

**Problem:** You cannot explicitly remove `restricted-v2` because it's granted to all authenticated users by default.

---

## Method 2: Force Custom SCC by Setting Deployment Security Context

Make your deployment request something that `restricted-v2` does NOT allow, forcing OpenShift to use your custom SCC.

### Step 1: Ensure Custom SCC Exists and is Bound

```bash
# Create custom SCC (if not already created)
cat <<EOF | oc apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: merchant-portal-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
allowedCapabilities: []
defaultAddCapabilities: []
fsGroup:
  type: MustRunAs
  ranges:
  - min: 1
    max: 65535
priority: 10
readOnlyRootFilesystem: false
requiredDropCapabilities:
- ALL
runAsUser:
  type: MustRunAsRange
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
users: []
groups: []
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
EOF

# Bind to service account
oc adm policy add-scc-to-user merchant-portal-scc -z merchant-portal-icashpro -n nmp-web-preprod

# Verify binding
oc describe scc merchant-portal-scc | grep -A 5 Users
```

### Step 2: Set fsGroup in Deployment to Force Custom SCC

`restricted-v2` has strict fsGroup rules. By explicitly setting fsGroup, you can force your custom SCC.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: merchant-portal
  namespace: nmp-web-preprod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: merchant-portal
  template:
    metadata:
      labels:
        app: merchant-portal
    spec:
      serviceAccountName: merchant-portal-icashpro
      securityContext:
        fsGroup: 1000790000          # Force specific fsGroup
        runAsUser: 1000790000         # Match your Dockerfile user
        runAsNonRoot: true
      containers:
      - name: merchant-portal
        image: registry-url/merchant-portal:latest
        ports:
        - containerPort: 4200
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsNonRoot: true
```

### Step 3: Apply and Verify

```bash
# Apply deployment
oc apply -f deployment.yaml -n nmp-web-preprod

# Delete old pods to force recreation
oc delete pod -l app=merchant-portal -n nmp-web-preprod

# Wait for new pod
oc get pods -n nmp-web-preprod -w

# Verify which SCC is now used
NEW_POD=$(oc get pods -n nmp-web-preprod -l app=merchant-portal -o jsonpath='{.items[0].metadata.name}')
oc get pod $NEW_POD -n nmp-web-preprod -o yaml | grep "openshift.io/scc"

# Should now show: merchant-portal-scc (or your custom SCC name)
```

---

## Method 3: Use Specific runAsUser That restricted-v2 Doesn't Allow

`restricted-v2` requires `runAsUser` to be within namespace's allocated range. Force a specific UID outside this range.

### Step 1: Check Namespace UID Range

```bash
# Check namespace annotations for UID range
oc get namespace nmp-web-preprod -o yaml | grep -i uid

# Output example:
# openshift.io/sa.scc.uid-range: 1001180000/10000
# This means allowed range is 1001180000 to 1001189999
```

### Step 2: Update Custom SCC to Allow Specific UID

```bash
oc edit scc merchant-portal-scc

# Change runAsUser section to:
runAsUser:
  type: MustRunAsRange
  uidRangeMin: 1000790000
  uidRangeMax: 1000790000
```

### Step 3: Set Deployment to Use That Specific UID

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: merchant-portal
  namespace: nmp-web-preprod
spec:
  template:
    spec:
      serviceAccountName: merchant-portal-icashpro
      securityContext:
        runAsUser: 1000790000        # Outside restricted-v2 allowed range
        fsGroup: 1000790000
        runAsNonRoot: true
      containers:
      - name: merchant-portal
        image: registry-url/merchant-portal:latest
        ports:
        - containerPort: 4200
```

---

## Method 4: Set SCC Priority Higher Than restricted-v2

OpenShift considers SCC priority when multiple SCCs match. Set your custom SCC priority higher.

```bash
# Check restricted-v2 priority
oc get scc restricted-v2 -o jsonpath='{.priority}'
# Usually returns: null (treated as 0)

# Set your custom SCC priority higher
oc patch scc merchant-portal-scc -p '{"priority": 10}' --type=merge

# Verify
oc get scc merchant-portal-scc -o jsonpath='{.priority}'

# Recreate pods
oc delete pod -l app=merchant-portal -n nmp-web-preprod
```

**Note:** Priority alone may not be enough. OpenShift still prefers most restrictive SCC.

---

## Method 5: Use RoleBinding to Grant SCC Access (Most Reliable)

Instead of adding SCC directly to user, create a Role and RoleBinding.

### Step 1: Create Role for SCC

```bash
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: use-merchant-portal-scc
  namespace: nmp-web-preprod
rules:
- apiGroups:
  - security.openshift.io
  resourceNames:
  - merchant-portal-scc
  resources:
  - securitycontextconstraints
  verbs:
  - use
EOF
```

### Step 2: Create RoleBinding

```bash
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: merchant-portal-icashpro-use-scc
  namespace: nmp-web-preprod
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: use-merchant-portal-scc
subjects:
- kind: ServiceAccount
  name: merchant-portal-icashpro
  namespace: nmp-web-preprod
EOF
```

### Step 3: Remove Old SCC Binding

```bash
# Remove the old policy binding
oc adm policy remove-scc-from-user merchant-portal-scc -z merchant-portal-icashpro -n nmp-web-preprod

# Verify RoleBinding exists
oc get rolebinding merchant-portal-icashpro-use-scc -n nmp-web-preprod
```

### Step 4: Set Deployment securityContext to Require Custom SCC

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: merchant-portal
  namespace: nmp-web-preprod
spec:
  template:
    spec:
      serviceAccountName: merchant-portal-icashpro
      securityContext:
        fsGroup: 1000790000
        runAsUser: 1000790000
        runAsNonRoot: true
      containers:
      - name: merchant-portal
        image: registry-url/merchant-portal:latest
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsNonRoot: true
```

---

## Complete Working Example

Here's a complete example that should force custom SCC usage:

### 1. Custom SCC Definition

```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: merchant-portal-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
allowedCapabilities: []
defaultAddCapabilities: []
fsGroup:
  type: MustRunAs
  ranges:
  - min: 1000790000
    max: 1000790000
priority: 10
readOnlyRootFilesystem: false
requiredDropCapabilities:
- ALL
runAsUser:
  type: MustRunAsRange
  uidRangeMin: 1000790000
  uidRangeMax: 1000790000
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
users:
- system:serviceaccount:nmp-web-preprod:merchant-portal-icashpro
```

### 2. Apply SCC

```bash
oc apply -f merchant-portal-scc.yaml
```

### 3. Deployment with Explicit Security Context

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: merchant-portal
  namespace: nmp-web-preprod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: merchant-portal
  template:
    metadata:
      labels:
        app: merchant-portal
    spec:
      serviceAccountName: merchant-portal-icashpro
      securityContext:
        fsGroup: 1000790000
        runAsUser: 1000790000
        runAsNonRoot: true
        seLinuxOptions:
          level: "s0:c26,c0"
      containers:
      - name: merchant-portal
        image: registry-url/merchant-portal:latest
        ports:
        - containerPort: 4200
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsNonRoot: true
```

### 4. Apply and Verify

```bash
# Apply deployment
oc apply -f deployment.yaml

# Delete old pods
oc delete pod -l app=merchant-portal -n nmp-web-preprod

# Wait and check
oc get pods -n nmp-web-preprod -w

# Verify SCC
NEW_POD=$(oc get pods -n nmp-web-preprod -l app=merchant-portal -o jsonpath='{.items[0].metadata.name}')
echo "Pod is using SCC:"
oc get pod $NEW_POD -n nmp-web-preprod -o yaml | grep "openshift.io/scc"

# Verify readOnlyRootFilesystem
echo "ReadOnlyRootFilesystem setting:"
oc get pod $NEW_POD -n nmp-web-preprod -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
echo

# Test write access
echo "Testing write access:"
oc rsh $NEW_POD -n nmp-web-preprod touch /opt/app-root/src/web-content/test.txt
oc rsh $NEW_POD -n nmp-web-preprod ls -la /opt/app-root/src/web-content/test.txt
```

---

## Troubleshooting: Still Using restricted-v2

If pod still shows `restricted-v2` after all attempts:

### Debug Steps

```bash
# 1. Check if service account can use your SCC
oc describe sa merchant-portal-icashpro -n nmp-web-preprod

# 2. Check SCC users list
oc describe scc merchant-portal-scc | grep -A 10 Users

# 3. Check pod events for SCC selection reasoning
oc describe pod $NEW_POD -n nmp-web-preprod | grep -A 20 Events

# 4. Enable SCC audit logging (requires cluster-admin)
oc get pod -n openshift-kube-apiserver -o name | head -1 | xargs -I {} oc logs {} -n openshift-kube-apiserver | grep -i scc

# 5. Check if namespace has any SCC restrictions
oc get namespace nmp-web-preprod -o yaml

# 6. Verify no admission webhooks are overriding SCC
oc get validatingwebhookconfiguration
oc get mutatingwebhookconfiguration
```

### Force SCC by Making Deployment Incompatible with restricted-v2

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: merchant-portal
  namespace: nmp-web-preprod
spec:
  template:
    spec:
      serviceAccountName: merchant-portal-icashpro
      hostNetwork: false
      hostPID: false
      hostIPC: false
      securityContext:
        runAsUser: 1000790000          # Specific UID outside namespace range
        runAsGroup: 1000790000
        fsGroup: 1000790000
        runAsNonRoot: true
      containers:
      - name: merchant-portal
        image: registry-url/merchant-portal:latest
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsNonRoot: true
          runAsUser: 1000790000
```

---

## Important Note

**Why This Is Complex:**

OpenShift's SCC admission controller is designed to be secure by default. It will ALWAYS try to use the most restrictive SCC that satisfies the pod's requirements. The only reliable way to force a less restrictive SCC is to:

1. Make the pod explicitly request something `restricted-v2` doesn't allow
2. Have a custom SCC that allows that specific thing
3. Ensure the service account has access to that custom SCC

**Recommended Approach:**

Instead of fighting the SCC system, **use emptyDir volume** which works perfectly with `restricted-v2`. This is the OpenShift-recommended pattern for applications that need writable directories.

---

## Summary: Methods to Override restricted-v2

| Method | Complexity | Success Rate | Recommended |
|--------|-----------|--------------|-------------|
| emptyDir volume | Low | 100% | ✅ Yes |
| Set explicit fsGroup/runAsUser | Medium | 80% | ⚠️ Maybe |
| Custom SCC with priority | Medium | 60% | ⚠️ Maybe |
| RoleBinding for SCC | High | 70% | ⚠️ If needed |
| Remove restricted-v2 access | Impossible | 0% | ❌ No |

**Best Solution:** Use emptyDir volume mount - it's simpler, more secure, and follows OpenShift best practices.