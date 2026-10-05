# OC CLI Commands to Force Service Account to Use Custom SCC (Not restricted-v2)

## Problem
Service account uses `restricted-v2` by default. Need to force it to use custom SCC instead.

---

## Quick Command Reference

### Step 1: Create Custom SCC (YAML Method)

```bash
# Create SCC YAML file
cat > merchant-portal-scc.yaml <<'EOF'
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
EOF

# Apply the SCC
oc apply -f merchant-portal-scc.yaml

# Verify SCC created
oc get scc merchant-portal-scc
```

### Step 2: Add Service Account to SCC Users List (Direct Method)

```bash
# Method 1: Add via oc patch (RECOMMENDED)
oc patch scc merchant-portal-scc --type=json -p '[
  {
    "op": "add",
    "path": "/users/-",
    "value": "system:serviceaccount:nmp-web-preprod:merchant-portal-icashpro"
  }
]'

# Method 2: Add via oc adm policy
oc adm policy add-scc-to-user merchant-portal-scc -z merchant-portal-icashpro -n nmp-web-preprod

# Verify service account is in SCC users list
oc get scc merchant-portal-scc -o jsonpath='{.users}' | grep merchant-portal-icashpro
```

### Step 3: Set SCC Priority Higher Than restricted-v2

```bash
# Check current priority of restricted-v2
oc get scc restricted-v2 -o jsonpath='{.priority}'

# Set custom SCC priority to 10 (higher than restricted-v2's null/0)
oc patch scc merchant-portal-scc -p '{"priority": 10}' --type=merge

# Verify priority
oc get scc merchant-portal-scc -o jsonpath='{.priority}'
```

### Step 4: Update Deployment with Explicit Security Context

```bash
# Create deployment patch file
cat > deployment-patch.yaml <<'EOF'
spec:
  template:
    spec:
      securityContext:
        fsGroup: 1000790000
        runAsUser: 1000790000
        runAsNonRoot: true
      containers:
      - name: merchant-portal
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsNonRoot: true
EOF

# Apply patch to deployment
oc patch deployment merchant-portal -n nmp-web-preprod --patch-file deployment-patch.yaml

# Or use inline patch
oc patch deployment merchant-portal -n nmp-web-preprod -p '
{
  "spec": {
    "template": {
      "spec": {
        "securityContext": {
          "fsGroup": 1000790000,
          "runAsUser": 1000790000,
          "runAsNonRoot": true
        }
      }
    }
  }
}'
```

### Step 5: Force Pod Recreation

```bash
# Delete existing pods to force recreation with new SCC
oc delete pod -l app=merchant-portal -n nmp-web-preprod

# Watch pods being recreated
oc get pods -n nmp-web-preprod -w

# Or rollout restart
oc rollout restart deployment/merchant-portal -n nmp-web-preprod
```

### Step 6: Verify Custom SCC is Being Used

```bash
# Get the new pod name
NEW_POD=$(oc get pods -n nmp-web-preprod -l app=merchant-portal -o jsonpath='{.items[0].metadata.name}')

# Check which SCC is being used
oc get pod $NEW_POD -n nmp-web-preprod -o yaml | grep "openshift.io/scc"

# Should output: openshift.io/scc: merchant-portal-scc
# If it shows restricted-v2, continue troubleshooting below
```

---

## Complete One-Liner Workflow

```bash
# All steps in sequence
oc create -f - <<'EOF'
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
EOF

# Patch deployment
oc patch deployment merchant-portal -n nmp-web-preprod -p '{"spec":{"template":{"spec":{"securityContext":{"fsGroup":1000790000,"runAsUser":1000790000,"runAsNonRoot":true}}}}}'

# Force recreation
oc delete pod -l app=merchant-portal -n nmp-web-preprod

# Verify
sleep 10
NEW_POD=$(oc get pods -n nmp-web-preprod -l app=merchant-portal -o jsonpath='{.items[0].metadata.name}')
oc get pod $NEW_POD -n nmp-web-preprod -o yaml | grep "openshift.io/scc"
```

---

## Troubleshooting Commands

### If Pod Still Shows restricted-v2

```bash
# 1. Verify SCC exists
oc get scc merchant-portal-scc

# 2. Check SCC users list
oc get scc merchant-portal-scc -o yaml | grep -A 10 users

# 3. Verify service account can access SCC
oc describe sa merchant-portal-icashpro -n nmp-web-preprod | grep -i scc

# 4. Check SCC priority
oc get scc merchant-portal-scc -o jsonpath='{.priority}'

# 5. Check namespace UID range
oc get namespace nmp-web-preprod -o yaml | grep -i uid

# 6. Verify deployment security context
oc get deployment merchant-portal -n nmp-web-preprod -o yaml | grep -A 10 securityContext

# 7. Check pod events for SCC admission errors
oc describe pod $NEW_POD -n nmp-web-preprod | grep -A 20 Events

# 8. Get detailed SCC matching info (if available)
oc get pod $NEW_POD -n nmp-web-preprod -o yaml | grep -A 20 annotations
```

### Fix Commands If Still Using restricted-v2

```bash
# Force specific user in SCC users list
oc patch scc merchant-portal-scc --type=json -p '[
  {
    "op": "add",
    "path": "/users",
    "value": ["system:serviceaccount:nmp-web-preprod:merchant-portal-icashpro"]
  }
]'

# Increase priority even higher
oc patch scc merchant-portal-scc -p '{"priority": 100}' --type=merge

# Force fsGroup range that restricted-v2 doesn't allow
oc patch deployment merchant-portal -n nmp-web-preprod -p '{"spec":{"template":{"spec":{"securityContext":{"fsGroup":1000790000,"fsGroupChangePolicy":"OnRootMismatch"}}}}}'

# Delete and recreate deployment completely
oc delete deployment merchant-portal -n nmp-web-preprod
oc create deployment merchant-portal --image=registry-url/merchant-portal:latest -n nmp-web-preprod
oc patch deployment merchant-portal -n nmp-web-preprod -p '{"spec":{"template":{"spec":{"serviceAccountName":"merchant-portal-icashpro","securityContext":{"fsGroup":1000790000,"runAsUser":1000790000,"runAsNonRoot":true}}}}}'
```

---

## Alternative: Use RBAC RoleBinding

```bash
# Create Role for SCC
oc create -f - <<'EOF'
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

# Create RoleBinding
oc create rolebinding merchant-portal-icashpro-use-scc \
  --role=use-merchant-portal-scc \
  --serviceaccount=nmp-web-preprod:merchant-portal-icashpro \
  -n nmp-web-preprod

# Verify RoleBinding
oc get rolebinding merchant-portal-icashpro-use-scc -n nmp-web-preprod -o yaml

# Remove old policy binding
oc adm policy remove-scc-from-user merchant-portal-scc -z merchant-portal-icashpro -n nmp-web-preprod

# Recreate pods
oc delete pod -l app=merchant-portal -n nmp-web-preprod
```

---

## Verification Commands

```bash
# Complete verification checklist
echo "=== SCC Verification ==="
oc get scc merchant-portal-scc

echo -e "\n=== SCC Users List ==="
oc get scc merchant-portal-scc -o jsonpath='{.users}' | tr ',' '\n'

echo -e "\n=== SCC Priority ==="
oc get scc merchant-portal-scc -o jsonpath='{.priority}'

echo -e "\n=== Service Account SCCs ==="
oc describe sa merchant-portal-icashpro -n nmp-web-preprod

echo -e "\n=== Current Pod SCC ==="
POD=$(oc get pods -n nmp-web-preprod -l app=merchant-portal -o jsonpath='{.items[0].metadata.name}')
oc get pod $POD -n nmp-web-preprod -o yaml | grep "openshift.io/scc"

echo -e "\n=== Pod Security Context ==="
oc get pod $POD -n nmp-web-preprod -o jsonpath='{.spec.securityContext}' | jq

echo -e "\n=== Container Security Context ==="
oc get pod $POD -n nmp-web-preprod -o jsonpath='{.spec.containers[0].securityContext}' | jq

echo -e "\n=== ReadOnly Root Filesystem ==="
oc get pod $POD -n nmp-web-preprod -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'

echo -e "\n=== Test Write Access ==="
oc rsh $POD -n nmp-web-preprod touch /opt/app-root/src/web-content/test.txt 2>&1
oc rsh $POD -n nmp-web-preprod ls -la /opt/app-root/src/web-content/test.txt 2>&1
```

---

## Expected Output After Success

```bash
$ oc get pod $NEW_POD -n nmp-web-preprod -o yaml | grep "openshift.io/scc"
openshift.io/scc: merchant-portal-scc

$ oc get pod $NEW_POD -n nmp-web-preprod -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
false

$ oc rsh $NEW_POD -n nmp-web-preprod touch /opt/app-root/src/web-content/test.txt
$ echo $?
0

$ oc logs $NEW_POD -n nmp-web-preprod | grep -i eacces
# No output (no errors)
```

---

## Quick Cleanup (If Needed)

```bash
# Remove custom SCC
oc delete scc merchant-portal-scc

# Remove SCC binding
oc adm policy remove-scc-from-user merchant-portal-scc -z merchant-portal-icashpro -n nmp-web-preprod

# Remove RoleBinding (if created)
oc delete rolebinding merchant-portal-icashpro-use-scc -n nmp-web-preprod

# Remove Role (if created)
oc delete role use-merchant-portal-scc -n nmp-web-preprod
```

---

## Important Notes

1. **Priority alone is not enough** - OpenShift will still choose `restricted-v2` if it satisfies pod requirements
2. **Must set explicit securityContext** in deployment to force custom SCC
3. **Must delete pods** after changes - old pods keep old SCC
4. **UID must be outside namespace range** for `restricted-v2` to be rejected
5. **Best practice:** Use emptyDir volume instead of fighting SCC system

---

## If All Else Fails: Use emptyDir Volume

```bash
# This ALWAYS works with restricted-v2
oc patch deployment merchant-portal -n nmp-web-preprod -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "merchant-portal",
          "volumeMounts": [{
            "name": "web-content-writable",
            "mountPath": "/opt/app-root/src/web-content"
          }]
        }],
        "volumes": [{
          "name": "web-content-writable",
          "emptyDir": {}
        }]
      }
    }
  }
}'

# Restart
oc rollout restart deployment/merchant-portal -n nmp-web-preprod
```