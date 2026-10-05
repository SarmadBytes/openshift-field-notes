# Debugging Commands

## Pod Debugging

### Get Pod Status
```bash
# Quick status check
oc get pods

# Detailed pod info
oc describe pod POD_NAME

# Watch pod status changes
oc get pods -w
```

### View Logs
```bash
# Current logs
oc logs POD_NAME

# Previous container logs (after crash)
oc logs POD_NAME --previous

# Follow logs in real-time
oc logs -f POD_NAME

# Logs from specific container
oc logs POD_NAME -c CONTAINER_NAME

# Last 50 lines
oc logs POD_NAME --tail=50
```

### Debug Running Pod
```bash
# Open shell in running pod
oc rsh POD_NAME

# Execute command in pod
oc exec POD_NAME -- COMMAND

# Debug with ephemeral container
oc debug POD_NAME
```

### Events and Errors
```bash
# See all events in namespace
oc get events --sort-by='.lastTimestamp'

# Events for specific pod
oc describe pod POD_NAME | grep -A 10 Events

# System-wide events
oc get events --all-namespaces
```

## Resource Debugging

### Check Resource Usage
```bash
# Node resources
oc adm top nodes

# Pod resource usage
oc adm top pods

# Container resource usage
oc adm top pods --containers
```

### Quota and Limits
```bash
# Check resource quotas
oc get resourcequota

# Check limit ranges
oc get limitrange

# Describe quota details
oc describe resourcequota
```

## Network Debugging

### Test Connectivity
```bash
# Test service endpoint
oc run -it --rm debug --image=busybox --restart=Never -- wget -qO- SERVICE_NAME:PORT

# DNS lookup test
oc run -it --rm debug --image=busybox --restart=Never -- nslookup SERVICE_NAME

# Port connectivity test
oc run -it --rm debug --image=nicolaka/netshoot --restart=Never -- nc -zv SERVICE_NAME PORT
```

### Service Debugging
```bash
# Check service endpoints
oc get endpoints

# Describe service
oc describe service SERVICE_NAME

# Test service from inside cluster
oc run curl --image=curlimages/curl --rm -it --restart=Never -- curl http://SERVICE_NAME
```

## Storage Debugging

### PVC Status
```bash
# List all PVCs
oc get pvc

# Describe PVC issues
oc describe pvc PVC_NAME

# Check PV status
oc get pv
```

### Mount Issues
```bash
# Check volume mounts in pod
oc describe pod POD_NAME | grep -A 5 Mounts

# Verify volume permissions
oc exec POD_NAME -- ls -la /mount/path
```

## Quick Troubleshooting Flow

```bash
# 1. Check pod status
oc get pods

# 2. If not running, check events
oc describe pod POD_NAME

# 3. Check logs
oc logs POD_NAME --previous

# 4. Check resource constraints
oc describe node
oc describe resourcequota

# 5. Debug interactively
oc debug POD_NAME
```