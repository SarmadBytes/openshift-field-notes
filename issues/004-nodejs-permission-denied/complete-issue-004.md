# Issue #004: Node.js Application Permission Denied Error in OpenShift

**Document Type:** Technical Resolution Guide
**Severity:** High
**Status:** Resolved
**Last Updated:** 2025-09-30

---

## Executive Summary

A Node.js application deployed via GitLab CI/CD fails to start in DMZ PreProd environment with `EACCES: permission denied` error when attempting to write to `./web-content/env.js`. Root cause identified as auto-injected `readOnlyRootFilesystem: true` security constraint by OpenShift's Security Context Constraints (SCC) admission controller in DMZ PreProd, which is not present in DEV environment.

**Resolution:** Mount emptyDir volume for writable directory or refactor application to use environment variables instead of runtime file writes.

---

## 1. Problem Statement

### 1.1 Environment Details

| Parameter | Value |
|-----------|-------|
| OpenShift Version | 4.x |
| Environment | DMZ PreProd |
| Namespace | nmp-web-preprod |
| Component | Node.js application pod |
| Service Account | merchant-portal-icashpro |
| Base Image | registry.access.redhat.com/ubi9/nodejs-20:1 |
| Deployment Method | GitLab CI/CD |

### 1.2 Issue Description

A Node.js application deployed through GitLab service account fails to start in DMZ PreProd environment with permission denied error when trying to write to `./web-content/env.js` file. The application attempts to write environment configuration at startup (`server.js:59`) but lacks permissions to modify the file.

### 1.3 Symptoms

- Pod starts but crashes immediately with EACCES error
- Error occurs during server.js initialization (line 59)
- Application tries to write to `./web-content/env.js` at runtime
- Same deployment works fine in DEV environment
- Issue only occurs in DMZ PreProd environment
- Pod status shows `CrashLoopBackOff`

### 1.4 Business Impact

- Application fails to start
- Complete service outage in PreProd DMZ
- Blocks deployment pipeline from GitLab
- Prevents testing in PreProd environment
- Delays release cycle

### 1.5 Environment Differences

| Environment | Status | Behavior |
|-------------|--------|----------|
| **DEV** | ✓ Working | Permissive SCC, no readOnlyRootFilesystem enforcement |
| **DMZ PreProd** | ✗ Failing | Strict SCC with readOnlyRootFilesystem: true auto-injected |

---

## 2. Technical Analysis

### 2.1 Error Log

```
$ oc logs merchant-portal-pod-xxxxx

Error: EACCES: permission denied, open './web-content/env.js'
at Object.writeFileSync (node:fs:2368:20)
at Object.<anonymous> (/opt/app-root/src/server.js:59:8)
at Module._compile (node:internal/modules/cjs/loader:1529:14)
at Module._extensions..js (node:internal/modules/cjs/loader:1613:10)
at Module.load (node:internal/modules/cjs/loader:1275:32)
at Module._load (node:internal/modules/cjs/loader:1096:12)
at I.loadModule (/opt/dynatrace/oneagent-paas/agent/bin/1.319.68.20250813-080958/any/nodejs/nodejsagent.js:20636:22)
at g.load (/opt/dynatrace/oneagent-paas/agent/bin/1.319.68.20250813-080958/any/nodejs/nodejsagent.js:20923:104)
at get moduleExports [as moduleExports] (/opt/dynatrace/oneagent-paas/agent/bin/1.319.68.20250813-080958/any/nodejs/nodejsagent.js:20911:12)
at Function._load (/opt/dynatrace/oneagent-paas/agent/bin/1.319.68.20250813-080958/any/nodejs/nodejsagent.js:20763:17) {
errno: -13,
code: 'EACCES',
syscall: 'open',
path: './web-content/env.js'
}
```

### 2.2 Dockerfile Configuration

```dockerfile
FROM registry.access.redhat.com/ubi9/nodejs-20:1

USER root

# Set working directory
WORKDIR /opt/app-root/src

# Create a user and group with the required UID and GID
RUN groupadd -g 1000790000 nodejs && \
    useradd -u 1000790000 -g nodejs -m -s /bin/bash nodejs

# Copy package.json and package-lock.json files with correct ownership
COPY --chown=nodejs:nodejs package.json ./

# Change ownership of the working directory to the new user
RUN chown -R nodejs:nodejs /opt/app-root/src

# Switch to the new user
USER nodejs

# Install app dependencies as non-root user
RUN npm install --force

# Copy the application source code
COPY --chown=nodejs:nodejs . .

EXPOSE 4200

CMD ["npm", "start"]
```

### 2.3 Pod Description (DMZ PreProd)

```
$ oc describe pod merchant-portal-pod-xxxxx

Name:         merchant-portal-pod-xxxxx
Namespace:    nmp-web-preprod
Service Account:  merchant-portal-icashpro
Security Context:
  FSGroup:            1000790000
  SELinux Options:    <none>

Containers:
  merchant-portal:
    Container ID:   cri-o://xxxxx
    Image:          registry-url/merchant-portal:latest
    State:          Waiting
      Reason:       CrashLoopBackOff
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
    Security Context:
      capabilities:
        drop:
          - ALL
      privileged: false
      runAsUser: 1001180000
      runAsGroup: 1001
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
```

### 2.4 Service Account Details

```
$ oc describe sa merchant-portal-icashpro

Name:                merchant-portal-icashpro
Namespace:           nmp-web-preprod
Labels:              <none>
Annotations:         <none>
Image pull secrets:  merchant-portal-icashpro-dockercfg-xxxxx
Mountable secrets:   merchant-portal-icashpro-dockercfg-xxxxx
Tokens:              merchant-portal-icashpro-token-xxxxx
Events:              <none>
```

### 2.5 Original Deployment YAML

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
        ports:
        - containerPort: 4200

# NOTE: No securityContext defined in original YAML
```

### 2.6 Auto-Injected Security Context (DMZ PreProd Only)

**Critical Finding:** The following securityContext is AUTOMATICALLY ADDED by OpenShift in DMZ PreProd:

```yaml
securityContext:
  capabilities:
    drop:
      - ALL
  privileged: false
  runAsUser: 1001180000
  runAsGroup: 1001
  runAsNonRoot: true
  readOnlyRootFilesystem: true        # <--- ROOT CAUSE
  allowPrivilegeEscalation: false
```

**Key Observations:**
- This security context is NOT in the original deployment YAML
- It is NOT present in DEV environment
- It is AUTOMATICALLY INJECTED in DMZ PreProd by Security Context Constraints (SCC)
- `readOnlyRootFilesystem: true` makes the entire container filesystem read-only
- `runAsUser: 1001180000` overrides the Dockerfile USER directive (nodejs:1000790000)

---

## 3. Root Cause Analysis

### 3.1 Root Cause

The application fails because **DMZ PreProd automatically injects a strict security context** that is NOT present in the original deployment YAML or in DEV environment.

#### What's Happening:

1. **Original YAML has NO securityContext**: The deployment manifest doesn't define any security context
2. **DMZ PreProd auto-injects security constraints**: OpenShift's Security Context Constraints (SCC) admission controller automatically adds strict security policies
3. **readOnlyRootFilesystem: true** makes the ENTIRE container filesystem read-only
4. **Application tries to write at runtime**: `server.js:59` attempts `fs.writeFileSync('./web-content/env.js')` which fails with EACCES error

### 3.2 Why DEV Works but PreProd Fails

| Aspect | DEV Environment | DMZ PreProd Environment |
|--------|----------------|------------------------|
| **SCC Policy** | Permissive (likely `anyuid`) | Strict (`restricted-v2`) |
| **readOnlyRootFilesystem** | Not enforced | Enforced (true) |
| **User UID** | Custom or flexible | Overridden to 1001180000 |
| **Auto-Injection** | Minimal or none | Full security context injected |

### 3.3 Technical Explanation

- **DEV**: Uses permissive SCC (likely `anyuid` or no readOnlyRootFilesystem enforcement)
- **DMZ PreProd**: Uses `restricted-v2` SCC which enforces `readOnlyRootFilesystem: true` for security compliance
- The Dockerfile's custom user (UID 1000790000) is overridden by OpenShift's assigned UID (1001180000)
- The key issue is that `/opt/app-root/src/web-content/` becomes read-only at runtime due to auto-injected security policies

---

## 4. Resolution

### 4.1 Solution 1: Use EmptyDir Volume for Writable Directory (Recommended)

Since `readOnlyRootFilesystem: true` is auto-injected, mount an emptyDir volume for the writable directory.

#### Updated Deployment YAML

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

#### Why This Works

- EmptyDir volumes are writable even when `readOnlyRootFilesystem: true`
- The volume is mounted OVER the read-only filesystem path
- Application can write `env.js` to the mounted emptyDir
- No security policy changes required
- Complies with security compliance requirements

#### Implementation Commands

```bash
# Apply the updated deployment
oc apply -f deployment.yaml

# Restart the deployment
oc rollout restart deployment/merchant-portal

# Monitor rollout status
oc rollout status deployment/merchant-portal
```

---

### 4.2 Solution 2: Modify Application to Use Environment Variables (Best Practice)

Better long-term solution - avoid writing files at runtime entirely.

#### Approach

1. Modify `server.js` to read from environment variables instead of writing `env.js`
2. Pass configuration through OpenShift ConfigMap or Secrets
3. Remove the `fs.writeFileSync` call at line 59

#### ConfigMap Implementation

```bash
# Create ConfigMap with application configuration
oc create configmap merchant-portal-config \
  --from-literal=API_URL=https://api.example.com \
  --from-literal=ENV=preprod \
  -n nmp-web-preprod
```

#### Updated Deployment with Environment Variables

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
        envFrom:
        - configMapRef:
            name: merchant-portal-config
```

#### Benefits

- Follows 12-factor app methodology
- No runtime file writes required
- Configuration externalized
- Easier to manage across environments
- More secure and maintainable

---

### 4.3 Solution 3: Investigate SCC Configuration

Investigate which SCC is causing the auto-injection.

```bash
# Check which SCC the pod is using
oc get pod merchant-portal-pod-xxxxx -o yaml | grep "openshift.io/scc"

# List all SCCs in the cluster
oc get scc

# Check SCC assigned to service account
oc describe scc restricted-v2

# View namespace-level SCC policies
oc get rolebinding -n nmp-web-preprod | grep scc

# Check pod security context
oc get pod merchant-portal-pod-xxxxx -o jsonpath='{.spec.containers[0].securityContext}' | jq
```

---

### 4.4 Solution 4: Create Custom SCC and Force Usage (Advanced - If Required)

**Warning:** Custom SCCs require security team approval. Solution 1 (emptyDir) is strongly preferred.

#### Issue: Pod Still Uses restricted-v2 After Creating Custom SCC

Even after creating a custom SCC and binding it to the service account, the pod may still use `restricted-v2` because OpenShift always chooses the MOST RESTRICTIVE SCC that satisfies pod requirements.

**Check which SCC is being used:**
```bash
oc get pod <pod-name> -n nmp-web-preprod -o yaml | grep "openshift.io/scc"
# If output shows: restricted-v2
# Then your custom SCC is NOT being applied
```

#### Step 1: Create Custom SCC with Explicit Service Account

```bash
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
```

#### Step 2: Update Deployment to Force Custom SCC Usage

Add explicit security context that `restricted-v2` doesn't allow:

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
        runAsUser: 1000790000         # Match Dockerfile user
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

#### Step 3: Apply and Force Pod Recreation

```bash
# Apply the updated deployment
oc apply -f deployment.yaml -n nmp-web-preprod

# Delete existing pods to force recreation with new SCC
oc delete pod -l app=merchant-portal -n nmp-web-preprod

# Wait for new pod
oc get pods -n nmp-web-preprod -w

# Get new pod name
NEW_POD=$(oc get pods -n nmp-web-preprod -l app=merchant-portal -o jsonpath='{.items[0].metadata.name}')

# Verify which SCC is now used
oc get pod $NEW_POD -n nmp-web-preprod -o yaml | grep "openshift.io/scc"
# Should now show: merchant-portal-scc

# Verify readOnlyRootFilesystem is false
oc get pod $NEW_POD -n nmp-web-preprod -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
# Should output: false (or empty)

# Test write access
oc rsh $NEW_POD -n nmp-web-preprod touch /opt/app-root/src/web-content/test.txt
oc rsh $NEW_POD -n nmp-web-preprod ls -la /opt/app-root/src/web-content/test.txt
```

#### Alternative Method: Use RoleBinding for SCC

```bash
# Create Role for SCC usage
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

# Create RoleBinding
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

# Verify RoleBinding
oc get rolebinding merchant-portal-icashpro-use-scc -n nmp-web-preprod
```

#### Troubleshooting: Still Using restricted-v2

If pod still shows `restricted-v2`:

```bash
# 1. Check namespace UID range
oc get namespace nmp-web-preprod -o yaml | grep uid
# Compare with your Dockerfile UID (1000790000)

# 2. Verify SCC is in service account's list
oc describe sa merchant-portal-icashpro -n nmp-web-preprod

# 3. Check SCC users list
oc get scc merchant-portal-scc -o yaml | grep -A 5 users

# 4. Set higher priority for custom SCC
oc patch scc merchant-portal-scc -p '{"priority": 10}' --type=merge

# 5. Delete deployment and recreate completely
oc delete deployment merchant-portal -n nmp-web-preprod
oc apply -f deployment.yaml
```

#### Why Custom SCC May Not Be Selected

OpenShift SCC selection logic:
1. Evaluates ALL SCCs that service account has access to
2. Scores each SCC based on how well it matches pod requirements
3. Selects the MOST RESTRICTIVE SCC that satisfies all requirements
4. `restricted-v2` is the default for all authenticated users

To force custom SCC, the deployment must explicitly request something that `restricted-v2` does NOT allow (like specific fsGroup/runAsUser outside namespace range).

**Recommended:** If fighting SCC selection is too complex, use Solution 1 (emptyDir volume) which works perfectly with `restricted-v2`.

---

## 5. Verification Steps

### 5.1 Post-Implementation Validation

```bash
# 1. Apply the deployment with volume mount
oc apply -f deployment.yaml

# 2. Watch pod status
oc get pods -w

# 3. Check if pod is running
oc get pods | grep merchant-portal

# 4. Verify pod is in Running state
oc get pods -n nmp-web-preprod

# 5. Check pod events
oc describe pod <pod-name> -n nmp-web-preprod

# 6. Verify write permissions in container
oc rsh merchant-portal-pod-xxxxx
$ ls -la /opt/app-root/src/web-content
$ touch /opt/app-root/src/web-content/test.txt
$ ls -la /opt/app-root/src/web-content/test.txt
$ exit

# 7. Check application logs for errors
oc logs merchant-portal-pod-xxxxx

# 8. Test application endpoint
curl http://merchant-portal-service:4200/health

# 9. Verify security context is still applied
oc get pod merchant-portal-pod-xxxxx -o yaml | grep -A 10 securityContext
```

### 5.2 Success Criteria

- ✓ Pod reaches Running state
- ✓ No CrashLoopBackOff errors
- ✓ Application logs show successful startup
- ✓ env.js file created in /opt/app-root/src/web-content
- ✓ Application endpoint responds correctly
- ✓ Security context constraints still enforced

---

## 6. Time to Resolution

| Phase | Time |
|-------|------|
| Investigation | 15 minutes |
| Implementation (emptyDir volume) | 5 minutes |
| Verification | 5 minutes |
| **Total** | **~25 minutes** |

---

## 7. Prevention & Best Practices

### 7.1 Design Principles

1. **Design for immutability**: Never write to application directories at runtime
2. **Use ConfigMaps/Secrets**: Store configuration externally, inject at pod startup
3. **Follow 12-factor app methodology**: Configuration should come from environment, not runtime file writes
4. **Assume restrictive SCCs**: Design applications expecting `readOnlyRootFilesystem: true`

### 7.2 Development Guidelines

1. **Test in production-like environments**: Ensure DEV and PreProd have similar SCC policies
2. **Document SCC requirements**: Track which SCCs each application needs
3. **Use volumes for writable data**: Mount emptyDir, PVC, or ConfigMaps for any runtime writes
4. **Review Dockerfile patterns**: Don't create custom users/groups unless absolutely necessary - use the image's default user
5. **Early SCC testing**: Test applications with the most restrictive SCC (`restricted-v2`) early in development

### 7.3 Environment Parity

- Maintain consistent SCC policies across DEV, TEST, and PROD environments
- Document any environment-specific security configurations
- Implement automated tests that validate application behavior under restrictive SCCs

---

## 8. Related Issues & References

### 8.1 Related Topics

- Security Context Constraints differences between environments
- Service account permission requirements
- Container filesystem immutability in OpenShift
- Auto-injection behavior by SCC admission controller
- OpenShift 4.x security hardening

### 8.2 Additional Resources

- [Red Hat OpenShift Security Context Constraints Documentation](https://docs.openshift.com)
- [12-Factor App Methodology](https://12factor.net)
- [OpenShift Container Platform Security Guide](https://docs.openshift.com/container-platform/latest/security/)
- Red Hat Knowledge Base: readOnlyRootFilesystem enforcement

---

## 9. Key Takeaways

### 9.1 Critical Findings

**Auto-Injected Security Context:**

The security context is **NOT in the original deployment YAML** but automatically added by OpenShift's SCC admission controller in DMZ PreProd:

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

### 9.2 Lessons Learned

1. **Environment discrepancies**: DEV uses permissive SCC without `readOnlyRootFilesystem` enforcement, while DMZ PreProd uses `restricted-v2` SCC
2. **UID override**: The Dockerfile's custom user (UID 1000790000) is overridden by OpenShift (UID 1001180000)
3. **Security policies vary**: Different namespace security policies exist between environments
4. **Design matters**: Applications must be designed for immutable infrastructure from the start

### 9.3 Recommended Approach

**Solution 1 (emptyDir volume)** is the recommended quick fix that maintains security compliance while allowing the application to function.

**Solution 2 (environment variables)** is the long-term best practice that should be implemented when refactoring is feasible.

---

**Document Version:** 1.0
**Author:** OpenShift Platform Team
**Review Date:** 2025-09-30
**Next Review:** 2025-12-30