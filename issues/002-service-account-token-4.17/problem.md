# Service Account Token Generation Issue After OpenShift 4.17 Upgrade

## Issue ID: 002
**Severity**: CRITICAL  
**Environment**: DMZ Cluster (OpenShift 4.17.33)  
**Date Identified**: 2025-01-23  

## Problem Description

After upgrading OpenShift from 4.16 to 4.17, multiple production applications are failing to start with service account errors. Pods are unable to authenticate and mount service account tokens that previously worked.

## Symptoms

- Pods stuck in ContainerCreating state
- ReplicaSets and StatefulSets unable to create pods
- Event logs showing: `serviceaccount "rec" not found`
- Applications in redis and gw-apps-prod namespaces completely down

## Error Messages

```
Warning   FailedCreate   replicaset/rec-services-rigger-79f6bb444c
Error creating: pods "rec-services-rigger-79f6bb444c-" is forbidden: 
error looking up service account redis/rec: serviceaccount "rec" not found

Warning   FailedCreate   statefulset/rec
create Pod rec-0 in StatefulSet rec failed error: pods "rec-0" is forbidden: 
error looking up service account redis/rec: serviceaccount "rec" not found
```

## Root Cause

OpenShift 4.17 introduced a breaking change in service account token generation:
- The `LegacyServiceAccountTokenNoAutoGeneration` feature gate is now enabled by default
- Service account API token secrets are no longer automatically created
- This aligns with upstream Kubernetes security best practices
- Applications relying on auto-generated tokens fail after the upgrade

## Impact

- **Business Impact**: Critical production services unavailable
- **Affected Services**: Redis cache, Gateway applications
- **User Impact**: Complete service outage for dependent applications
- **Recovery Time**: Immediate action required

## Technical Details

### What Changed in 4.17
1. Service accounts no longer get automatic token secrets
2. Existing tokens continue to work but new SAs have no tokens
3. TokenRequest API is now the preferred method
4. Long-lived tokens are considered a security risk

### Affected Components
- Namespace: redis
- Namespace: gw-apps-prod  
- Service Account: rec
- Deployments: rec-services-rigger
- StatefulSets: rec

## Related Issues
- OpenShift BZ#2094990 - Service Account token changes
- Kubernetes KEP-2799 - Bound Service Account Tokens