# Troubleshooting: SCC Changes Not Resolving Permission Error

**Issue:** After creating custom SCC or modifying SCC settings, the same `EACCES: permission denied` error persists.

---

## Why SCC Changes Alone Don't Work

Even after setting a custom SCC with `readOnlyRootFilesystem: false`, the error persists because:

1. **readOnlyRootFilesystem is only ONE constraint** - there are other permission issues at play
2. **Pod must be recreated** - Old pods don't automatically get new SCC settings
3. **SCC priority matters** - OpenShift may still be using a different SCC
4. **Directory ownership issues** - Even writable filesystem needs correct user permissions

---

## Step-by-Step Troubleshooting

### Step 1: Verify SCC is Actually Applied

```bash
# Check which SCC the pod is ACTUALLY using
oc get pod <pod-name> -n nmp-web-preprod -o yaml | grep "openshift.io/scc"

# Expected output should show your custom SCC
# If it shows "restricted" or "restricted-v2", your SCC is NOT applied
```

**If wrong SCC is shown:**
```bash
# Delete existing pods to force recreation
oc delete pod -l app=merchant-portal -n nmp-web-preprod

# Wait for new pods with correct SCC
oc get pods -n nmp-web-preprod -w
```

### Step 2: Verify SCC Binding to Service Account

```bash
# Check if SCC is bound to service account
oc get scc merchant-portal-scc -o yaml

# Look for service account in "users" section
# Should see: system:serviceaccount:nmp-web-preprod:merchant-portal-icashpro

# If not present, re-bind
oc adm policy add-scc-to-user merchant-portal-scc -z merchant-portal-icashpro -n nmp-web-preprod
```

### Step 3: Check SCC Priority

```bash
# List all SCCs the service account can use
oc describe sa merchant-portal-icashpro -n nmp-web-preprod

# OpenShift uses the MOST RESTRICTIVE SCC by default
# Your custom SCC must have higher priority than "restricted-v2"

# Check SCC priority
oc get scc merchant-portal-scc -o jsonpath='{.priority}'
oc get scc restricted-v2 -o jsonpath='{.priority}'
```

**Fix priority if needed:**
```bash
oc patch scc merchant-portal-scc -p '{"priority": 10}'
```

### Step 4: Verify Pod Security Context After Recreation

```bash
# Get new pod name
NEW_POD=$(oc get pods -n nmp-web-preprod -l app=merchant-portal -o jsonpath='{.items[0].metadata.name}')

# Check security context
oc get pod $NEW_POD -n nmp-web-preprod -o yaml | grep -A 10 "securityContext"

# Verify readOnlyRootFilesystem is now false
oc get pod $NEW_POD -n nmp-web-preprod -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'

# Should output: false (or nothing if not set)
```

### Step 5: Check Directory Permissions Inside Pod

```bash
# Even with writable filesystem, check if user can write to directory
oc rsh $NEW_POD -n nmp-web-preprod

# Inside pod:
$ whoami
$ id
$ ls -la /opt/app-root/src/
$ ls -la /opt/app-root/src/web-content/

# Check if directory exists and ownership
$ stat /opt/app-root/src/web-content/

# Try manual write test
$ touch /opt/app-root/src/web-content/test.txt
```

---

## Common Issues & Solutions

### Issue 1: SCC Not Applied - Pod Still Using restricted-v2

**Problem:** Pod still shows `restricted-v2` SCC after custom SCC creation

**Solution:**
```bash
# 1. Delete the deployment completely
oc delete deployment merchant-portal -n nmp-web-preprod

# 2. Verify SCC binding again
oc adm policy add-scc-to-user merchant-portal-scc -z merchant-portal-icashpro -n nmp-web-preprod

# 3. Recreate deployment
oc apply -f deployment.yaml

# 4. Verify new pod uses correct SCC
oc get pod <new-pod> -n nmp-web-preprod -o yaml | grep "openshift.io/scc"
```

### Issue 2: Directory Doesn't Exist or Wrong Ownership

**Problem:** `/opt/app-root/src/web-content/` doesn't exist or has wrong ownership

**Solution - Fix in Dockerfile:**
```dockerfile
FROM registry.access.redhat.com/ubi9/nodejs-20:1

USER root
WORKDIR /opt/app-root/src

# Create web-content directory with correct permissions
RUN mkdir -p /opt/app-root/src/web-content && \
    chown -R 1001:0 /opt/app-root/src && \
    chmod -R g+rw /opt/app-root/src/web-content

USER 1001

COPY --chown=1001:0 package.json ./
RUN npm install --force
COPY --chown=1001:0 . .

EXPOSE 4200
CMD ["npm", "start"]
```

### Issue 3: SELinux Blocking Write Operations

**Problem:** SELinux context preventing writes even with correct permissions

**Diagnosis:**
```bash
# Check for SELinux denials
oc rsh $NEW_POD -n nmp-web-preprod
$ ls -laZ /opt/app-root/src/web-content/
```

**Solution:**
```bash
# Add SELinux context to custom SCC
oc edit scc merchant-portal-scc

# Add/modify:
seLinuxContext:
  type: MustRunAs
```

### Issue 4: Pod Created Before SCC Binding

**Problem:** Pod was created before SCC was properly bound

**Solution:**
```bash
# Always delete and recreate pods after SCC changes
oc delete pod --all -n nmp-web-preprod

# Or scale down and up
oc scale deployment merchant-portal --replicas=0 -n nmp-web-preprod
oc scale deployment merchant-portal --replicas=1 -n nmp-web-preprod
```

---

## Recommended Solution: Use emptyDir Volume Instead

**Why this is better than SCC changes:**
- Works with existing restrictive SCCs
- No security team approvals needed
- Follows OpenShift best practices
- Maintains security compliance

**Implementation:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: merchant-portal
spec:
  template:
    spec:
      serviceAccountName: merchant-portal-icashpro
      containers:
      - name: merchant-portal
        image: registry-url/merchant-portal:latest
        volumeMounts:
        - name: web-content-writable
          mountPath: /opt/app-root/src/web-content
      volumes:
      - name: web-content-writable
        emptyDir: {}
```

```bash
# Apply and verify
oc apply -f deployment.yaml
oc rollout restart deployment/merchant-portal -n nmp-web-preprod
oc get pods -n nmp-web-preprod -w

# Test write access
oc rsh <new-pod> -n nmp-web-preprod
$ touch /opt/app-root/src/web-content/test.txt
$ ls -la /opt/app-root/src/web-content/test.txt
```

---

## Comprehensive Debugging Commands

```bash
# 1. Check current SCC assignment
oc get pod <pod-name> -n nmp-web-preprod -o yaml | grep -i scc

# 2. List all SCCs service account can use
oc describe sa merchant-portal-icashpro -n nmp-web-preprod | grep -A 20 "Policies"

# 3. Check pod's actual security context
oc get pod <pod-name> -n nmp-web-preprod -o jsonpath='{.spec.containers[0].securityContext}' | jq

# 4. Check pod events for SCC-related errors
oc describe pod <pod-name> -n nmp-web-preprod | grep -A 20 Events

# 5. Verify SCC allows necessary volumes
oc get scc merchant-portal-scc -o jsonpath='{.volumes}' | jq

# 6. Check namespace-level policies
oc get rolebinding -n nmp-web-preprod

# 7. Test with debug pod
oc debug deployment/merchant-portal -n nmp-web-preprod

# 8. Check admission webhook logs (cluster admin required)
oc logs -n openshift-kube-apiserver <apiserver-pod> | grep -i "scc"
```

---

## Final Verification Checklist

- [ ] Custom SCC exists: `oc get scc merchant-portal-scc`
- [ ] SCC bound to SA: `oc describe sa merchant-portal-icashpro | grep scc`
- [ ] Pod recreated after SCC changes: `oc get pod <pod> -o yaml | grep creationTimestamp`
- [ ] Pod using correct SCC: `oc get pod <pod> -o yaml | grep "openshift.io/scc"`
- [ ] readOnlyRootFilesystem is false: `oc get pod <pod> -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'`
- [ ] User ID matches: `oc rsh <pod> id`
- [ ] Directory exists: `oc rsh <pod> ls -la /opt/app-root/src/web-content`
- [ ] Write test succeeds: `oc rsh <pod> touch /opt/app-root/src/web-content/test.txt`
- [ ] Application starts: `oc logs <pod> | grep -i error`

---

## Key Insight

**The real issue is NOT just `readOnlyRootFilesystem: true`** - it's a combination of:
1. Read-only filesystem
2. Directory ownership/permissions
3. SELinux contexts
4. User ID mismatches
5. SCC priority and selection

**Best approach:** Use emptyDir volume mount (Solution 1) which bypasses all these issues while maintaining security compliance.