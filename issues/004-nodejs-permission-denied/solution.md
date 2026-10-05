# Solution

## Root Cause

The application fails because **DMZ PreProd automatically injects a strict security context** that is NOT present in the original deployment YAML or in DEV environment. Specifically:

### What's Happening:

1. **Original YAML has NO securityContext**: The deployment manifest doesn't define any security context
2. **DMZ PreProd auto-injects security constraints**: OpenShift's Security Context Constraints (SCC) admission controller automatically adds:
   ```yaml
   securityContext:
     readOnlyRootFilesystem: true    # <-- ROOT CAUSE
     runAsUser: 1001180000
     runAsGroup: 1001
     runAsNonRoot: true
     capabilities:
       drop: [ALL]
     allowPrivilegeEscalation: false
   ```
3. **readOnlyRootFilesystem: true** makes the ENTIRE container filesystem read-only
4. **Application tries to write at runtime**: `server.js:59` attempts `fs.writeFileSync('./web-content/env.js')` which fails with EACCES

### Why DEV Works but PreProd Fails:

- **DEV**: Uses permissive SCC (likely `anyuid` or no readOnlyRootFilesystem enforcement)
- **DMZ PreProd**: Uses `restricted-v2` SCC which enforces `readOnlyRootFilesystem: true` for security compliance
- The Dockerfile's custom user (UID 1000790000) is overridden by OpenShift's assigned UID (1001180000)

The key issue is that `/opt/app-root/src/web-content/` becomes read-only at runtime due to auto-injected security policies in DMZ PreProd.

## Fix Applied

### Solution 1: Use EmptyDir Volume for Writable Directory (Recommended)

Since `readOnlyRootFilesystem: true` is auto-injected, mount an emptyDir volume for the writable directory:

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

**Why this works:**
- EmptyDir volumes are writable even when `readOnlyRootFilesystem: true`
- The volume is mounted OVER the read-only filesystem path
- Application can write `env.js` to the mounted emptyDir

Apply the fix:
```bash
oc apply -f deployment.yaml
oc rollout restart deployment/merchant-portal
```

### Solution 2: Modify Application to Use Environment Variables

Better long-term solution - avoid writing files at runtime:

1. Modify `server.js` to read from environment variables instead of writing `env.js`
2. Pass configuration through OpenShift ConfigMap or Secrets
3. Remove the `fs.writeFileSync` call at line 59

Example ConfigMap approach:
```bash
oc create configmap merchant-portal-config \
  --from-literal=API_URL=https://api.example.com \
  --from-literal=ENV=preprod
```

Update deployment to inject as environment variables:
```yaml
envFrom:
- configMapRef:
    name: merchant-portal-config
```

### Solution 3: Check Which SCC is Auto-Injecting Security Context

Investigate which SCC is causing the auto-injection:

```bash
# Check which SCC the pod is using
oc get pod merchant-portal-pod-xxxxx -o yaml | grep "openshift.io/scc"

# List all SCCs in the cluster
oc get scc

# Check SCC assigned to service account
oc describe scc restricted-v2

# View namespace-level SCC policies
oc get rolebinding -n nmp-web-preprod | grep scc
```

### Solution 4: Create Custom SCC (Advanced - If Needed)

If Solutions 1 & 2 aren't feasible and security team approves, create a custom SCC:

```bash
# Create custom SCC that allows writable filesystem
cat <<EOF | oc apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: merchant-portal-scc
allowPrivilegeEscalation: false
allowedCapabilities: []
defaultAddCapabilities: []
fsGroup:
  type: RunAsAny
readOnlyRootFilesystem: false    # <-- Allow writable filesystem
requiredDropCapabilities:
- ALL
runAsUser:
  type: MustRunAsRange
seLinuxContext:
  type: MustRunAs
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
EOF

# Bind SCC to service account
oc adm policy add-scc-to-user merchant-portal-scc -z merchant-portal-icashpro -n nmp-web-preprod
```

**Warning**: Custom SCCs require security team approval. Solution 1 (emptyDir) is preferred.

## Verification Steps

```bash
# 1. Apply the deployment with volume mount
oc apply -f deployment.yaml

# 2. Watch pod status
oc get pods -w

# 3. Check if pod is running
oc get pods | grep merchant-portal

# 4. Verify write permissions in container
oc rsh merchant-portal-pod-xxxxx
$ ls -la /opt/app-root/src/web-content
$ touch /opt/app-root/src/web-content/test.txt
$ ls -la /opt/app-root/src/web-content/test.txt

# 5. Check application logs
oc logs merchant-portal-pod-xxxxx

# 6. Test application endpoint
curl http://merchant-portal-service:4200/health
```

## Time to Resolution

- Investigation: 15 minutes
- Implementation (emptyDir volume): 5 minutes
- Verification: 5 minutes
- Total: ~25 minutes

## Prevention

1. **Design for immutability**: Never write to application directories at runtime
2. **Use ConfigMaps/Secrets**: Store configuration externally, inject at pod startup
3. **Test in production-like environments**: Ensure DEV and PreProd have similar SCC policies
4. **Document SCC requirements**: Track which SCCs each application needs
5. **Use volumes for writable data**: Mount emptyDir, PVC, or ConfigMaps for any runtime writes
6. **Review Dockerfile patterns**: Don't create custom users/groups unless absolutely necessary - use the image's default user

## Related Issues

- Security Context Constraints differences between environments
- Service account permission requirements
- Container filesystem immutability in OpenShift

## Additional Notes

**Critical Finding - Auto-Injected Security Context:**

The security context shown below is **NOT in the original deployment YAML**:
```yaml
securityContext:
  capabilities:
    drop: [ALL]
  privileged: false
  runAsUser: 1001180000
  runAsGroup: 1001
  runAsNonRoot: true
  readOnlyRootFilesystem: true      # <-- Injected by DMZ PreProd SCC
  allowPrivilegeEscalation: false
```

This is automatically added by OpenShift's SCC admission controller in DMZ PreProd but NOT in DEV.

**Why it worked in DEV but not PreProd:**
- **DEV**: Uses permissive SCC without `readOnlyRootFilesystem` enforcement
- **DMZ PreProd**: Uses `restricted-v2` SCC which auto-injects `readOnlyRootFilesystem: true`
- The Dockerfile's custom user (UID 1000790000) is overridden by OpenShift (UID 1001180000)
- Different namespace security policies between environments

**Best Practice:**
1. Always design applications following the **12-factor app methodology** - configuration should come from environment, not runtime file writes
2. Assume `readOnlyRootFilesystem: true` will be enforced in production environments
3. Test applications with the most restrictive SCC (`restricted-v2`) early in development
4. Use emptyDir volumes for any temporary file writes needed at runtime