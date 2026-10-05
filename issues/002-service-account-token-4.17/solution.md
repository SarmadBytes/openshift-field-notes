# Solution: Service Account Token Generation Issue

## Quick Fix (Immediate Recovery)

### Step 1: Create Missing Service Accounts
```bash
# Check if service accounts exist
oc get sa -n redis
oc get sa -n gw-apps-prod

# Create missing service accounts
oc create serviceaccount rec -n redis
oc create serviceaccount rec -n gw-apps-prod
```

### Step 2: Create Long-Lived Token Secrets
```bash
# For redis namespace
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: rec-token
  namespace: redis
  annotations:
    kubernetes.io/service-account.name: rec
type: kubernetes.io/service-account-token
EOF

# For gw-apps-prod namespace
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: rec-token
  namespace: gw-apps-prod
  annotations:
    kubernetes.io/service-account.name: rec
type: kubernetes.io/service-account-token
EOF
```

### Step 3: Link Token to Service Account
```bash
# Link the secret to service account
oc patch serviceaccount rec -n redis \
  -p '{"secrets": [{"name": "rec-token"}]}'
  
oc patch serviceaccount rec -n gw-apps-prod \
  -p '{"secrets": [{"name": "rec-token"}]}'
```

### Step 4: Verify and Restart Pods
```bash
# Verify token creation
oc get secret rec-token -n redis
oc get secret rec-token -n gw-apps-prod

# Delete failed pods to trigger recreation
oc delete pods --field-selector=status.phase=Failed -n redis
oc delete pods --field-selector=status.phase=Failed -n gw-apps-prod

# Scale deployments to trigger new pod creation
oc rollout restart deployment/rec-services-rigger -n redis
oc rollout restart statefulset/rec -n redis
oc rollout restart deployment/rec-services-rigger -n gw-apps-prod
oc rollout restart statefulset/rec -n gw-apps-prod
```

## Permanent Solution (Best Practice)

### Option 1: Use Projected Volumes (Recommended)
Update your deployment to use projected service account tokens:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rec-services-rigger
spec:
  template:
    spec:
      serviceAccountName: rec
      containers:
      - name: app
        volumeMounts:
        - name: token
          mountPath: /var/run/secrets/tokens
      volumes:
      - name: token
        projected:
          sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 3600
              audience: api
```

### Option 2: Use TokenRequest API
For external access, use the TokenRequest API:

```bash
# Request a bound token
oc create token rec -n redis --duration=8760h

# Use in application configuration
export SA_TOKEN=$(oc create token rec -n redis)
```

### Option 3: Create Service Account with Token (Legacy)
If you must use legacy tokens, create them explicitly:

```bash
# Script to create SA with token
#!/bin/bash
NAMESPACE=$1
SA_NAME=$2

# Create service account
oc create sa ${SA_NAME} -n ${NAMESPACE}

# Create token secret
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SA_NAME}-token
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

# Wait for token controller
sleep 2

# Verify token
oc describe secret ${SA_NAME}-token -n ${NAMESPACE}
```

## Prevention Measures

### Pre-Upgrade Checklist
1. Audit all service accounts before upgrade
2. Document which applications use SA tokens
3. Test token generation in non-prod first
4. Create tokens manually before upgrade

### Post-Upgrade Validation
```bash
# Check all service accounts have tokens
for ns in $(oc get ns -o name | cut -d/ -f2); do
  echo "Namespace: $ns"
  oc get sa -n $ns -o json | jq '.items[] | {name: .metadata.name, secrets: .secrets}'
done
```

### Monitoring Script
```bash
#!/bin/bash
# Monitor for SA token issues
oc get events --all-namespaces | grep -i "serviceaccount.*not found"
oc get pods --all-namespaces | grep -E "ContainerCreating|Failed"
```

## Rollback Plan

If issues persist after applying fixes:

1. **Document all affected services**
2. **Create manual token secrets for all SAs**
3. **Consider cluster rollback if critical services remain down**

## References

- [Red Hat Solution 7071967](https://access.redhat.com/solutions/7071967)
- [OpenShift 4.17 Release Notes](https://docs.openshift.com/container-platform/4.17/release_notes/)
- [Kubernetes Bound Service Account Tokens](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#bound-service-account-token-volume)

## Lessons Learned

1. Always review breaking changes in release notes
2. Test upgrades in staging environment first
3. Have rollback plan ready before production upgrades
4. Monitor service account token usage proactively