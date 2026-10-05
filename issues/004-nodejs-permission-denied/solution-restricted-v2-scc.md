# Solution: Pod Still Using restricted-v2 SCC After Custom SCC Creation

## Problem Confirmed

Pod is using `restricted-v2` SCC even after creating custom SCC and binding it to service account.

```bash
$ oc get pod <pod-name> -n nmp-web-preprod -o yaml | grep "openshift.io/scc"
openshift.io/scc: restricted-v2
```

**Why this happens:** OpenShift's SCC admission controller chooses the MOST RESTRICTIVE SCC that a service account has access to. Your custom SCC exists but `restricted-v2` is being selected because it's more restrictive.

---

## Solution: Use emptyDir Volume (Works with restricted-v2)

**This is the correct approach** - Don't fight the SCC, work with it.

### Why This Works

- `restricted-v2` allows emptyDir volumes
- emptyDir volumes remain writable even with `readOnlyRootFilesystem: true`
- No SCC changes needed
- No security team approval required
- Maintains compliance

### Implementation

#### Step 1: Update Deployment YAML

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
      containers:
      - name: merchant-portal
        image: registry-url/merchant-portal:latest
        ports:
        - containerPort: 4200
        volumeMounts:
        - name: web-content-writable
          mountPath: /opt/app-root/src/web-content
      volumes:
      - name: web-content-writable
        emptyDir: {}
```

#### Step 2: Apply Changes

```bash
# Apply the updated deployment
oc apply -f deployment.yaml -n nmp-web-preprod

# Force rollout restart
oc rollout restart deployment/merchant-portal -n nmp-web-preprod

# Watch pod status
oc get pods -n nmp-web-preprod -w
```

#### Step 3: Verify Solution

```bash
# Get new pod name
NEW_POD=$(oc get pods -n nmp-web-preprod -l app=merchant-portal -o jsonpath='{.items[0].metadata.name}')

# Verify pod is running
oc get pod $NEW_POD -n nmp-web-preprod

# Check if volume is mounted
oc describe pod $NEW_POD -n nmp-web-preprod | grep -A 5 "Mounts:"

# Verify SCC (should still be restricted-v2, but that's OK now)
oc get pod $NEW_POD -n nmp-web-preprod -o yaml | grep "openshift.io/scc"

# Test write access inside pod
oc rsh $NEW_POD -n nmp-web-preprod

# Inside the pod:
$ ls -la /opt/app-root/src/web-content
$ touch /opt/app-root/src/web-content/test.txt
$ ls -la /opt/app-root/src/web-content/test.txt
$ echo "test" > /opt/app-root/src/web-content/env.js
$ cat /opt/app-root/src/web-content/env.js
$ exit

# Check application logs
oc logs $NEW_POD -n nmp-web-preprod

# Verify no more EACCES errors
oc logs $NEW_POD -n nmp-web-preprod | grep -i "EACCES"
```

---

## Alternative: If emptyDir Volume Has Issues

If for some reason emptyDir doesn't work or you need pre-existing content in the directory:

### Option A: Pre-populate emptyDir with InitContainer

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
      initContainers:
      - name: setup-web-content
        image: registry-url/merchant-portal:latest
        command: ['sh', '-c', 'cp -r /opt/app-root/src/web-content-original/* /opt/app-root/src/web-content/ || true']
        volumeMounts:
        - name: web-content-writable
          mountPath: /opt/app-root/src/web-content
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

### Option B: Use ConfigMap for Static Content + emptyDir for env.js

```bash
# Create ConfigMap from existing web-content files (if any)
oc create configmap web-content-static --from-file=./web-content/ -n nmp-web-preprod
```

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
      containers:
      - name: merchant-portal
        image: registry-url/merchant-portal:latest
        volumeMounts:
        - name: web-content-static
          mountPath: /opt/app-root/src/web-content/static
          readOnly: true
        - name: web-content-writable
          mountPath: /opt/app-root/src/web-content/dynamic
      volumes:
      - name: web-content-static
        configMap:
          name: web-content-static
      - name: web-content-writable
        emptyDir: {}
```

Then modify `server.js` to write to `/opt/app-root/src/web-content/dynamic/env.js` instead.

---

## Why Custom SCC Doesn't Override restricted-v2

Understanding OpenShift SCC selection logic:

1. **OpenShift evaluates ALL SCCs** that the service account has access to
2. **It scores each SCC** based on how well it matches pod requirements
3. **It selects the MOST RESTRICTIVE** SCC that satisfies all requirements
4. **restricted-v2 is the default** for all authenticated users

Even if you create a custom SCC with higher priority, OpenShift will still choose `restricted-v2` if:
- Your pod doesn't request anything that `restricted-v2` denies
- `restricted-v2` scores higher on restrictiveness

### To Force Custom SCC Usage

If you ABSOLUTELY must use custom SCC instead of emptyDir:

```bash
# Method 1: Remove access to restricted-v2 (NOT RECOMMENDED - may break other pods)
# This requires cluster-admin and is generally a bad idea

# Method 2: Make pod request something restricted-v2 denies
# Add this to deployment - but this defeats the purpose of security
```

**DO NOT DO THIS** - The emptyDir approach is the correct solution.

---

## Expected Behavior After emptyDir Fix

### Before (with restricted-v2 and no emptyDir):
```bash
$ oc logs merchant-portal-pod
Error: EACCES: permission denied, open './web-content/env.js'
errno: -13
code: 'EACCES'
```

### After (with restricted-v2 and emptyDir):
```bash
$ oc logs merchant-portal-pod
Server starting...
Environment file created: /opt/app-root/src/web-content/env.js
Application running on port 4200
```

### Verification Commands:
```bash
# Pod should be Running
$ oc get pods -n nmp-web-preprod
NAME                               READY   STATUS    RESTARTS   AGE
merchant-portal-xxxxxxxxxx-xxxxx   1/1     Running   0          2m

# Still using restricted-v2 (this is correct)
$ oc get pod <pod> -n nmp-web-preprod -o yaml | grep "openshift.io/scc"
openshift.io/scc: restricted-v2

# But readOnlyRootFilesystem is true (this is also correct)
$ oc get pod <pod> -n nmp-web-preprod -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
true

# And volume is mounted and writable
$ oc rsh <pod> -n nmp-web-preprod touch /opt/app-root/src/web-content/test.txt
$ oc rsh <pod> -n nmp-web-preprod ls -la /opt/app-root/src/web-content/test.txt
-rw-r--r--. 1 1001180000 root 0 Sep 30 14:30 /opt/app-root/src/web-content/test.txt
```

---

## Summary

✅ **Correct Approach:** Add emptyDir volume to deployment
- Works with `restricted-v2` SCC
- No security policy changes needed
- Maintains compliance
- Simple and effective

❌ **Incorrect Approach:** Try to override restricted-v2 with custom SCC
- Requires cluster-admin privileges
- May not work due to SCC selection logic
- Creates security policy exceptions
- More complex and error-prone

---

## Complete Working Deployment Example

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
      version: v1
  template:
    metadata:
      labels:
        app: merchant-portal
        version: v1
    spec:
      serviceAccountName: merchant-portal-icashpro
      containers:
      - name: merchant-portal
        image: registry-url/merchant-portal:latest
        ports:
        - containerPort: 4200
          protocol: TCP
        env:
        - name: NODE_ENV
          value: "preprod"
        volumeMounts:
        - name: web-content-writable
          mountPath: /opt/app-root/src/web-content
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 4200
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 4200
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: web-content-writable
        emptyDir: {}
```

Save this as `deployment.yaml` and apply:
```bash
oc apply -f deployment.yaml -n nmp-web-preprod
```

---

## Next Steps

1. ✅ Apply deployment with emptyDir volume
2. ✅ Verify pod reaches Running state
3. ✅ Confirm no EACCES errors in logs
4. ✅ Test application functionality
5. ✅ Remove custom SCC if it was created (optional cleanup)

```bash
# Optional: Remove custom SCC since we don't need it
oc delete scc merchant-portal-scc
oc adm policy remove-scc-from-user merchant-portal-scc -z merchant-portal-icashpro -n nmp-web-preprod
```