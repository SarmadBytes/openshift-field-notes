# Solution

## Root Cause
The application was running out of memory. The Java heap space error indicated the app needed more memory than the 256Mi limit configured in the deployment. The v2.1 update included a larger data cache that required more memory.

## Fix Applied

### Step 1: Identify Memory Issue
```bash
oc logs myapp-deployment-7b9f8-x2kp | grep -i memory
```
Found "OutOfMemoryError: Java heap space" confirming memory exhaustion.

### Step 2: Check Current Limits
```bash
oc get deployment myapp-deployment -o yaml | grep -A2 resources
```
Showed memory limit of 256Mi which was insufficient.

### Step 3: Update Memory Limits
```bash
oc set resources deployment/myapp-deployment --limits=memory=512Mi --requests=memory=256Mi
```

### Step 4: Verify Fix
```bash
oc rollout status deployment/myapp-deployment
oc get pods -w
```
Pod started successfully and remained running.

## Time to Resolution
- Investigation: 10 minutes
- Implementation: 5 minutes
- Total: 15 minutes

## Prevention
- Always load test new versions before production deployment
- Monitor memory usage trends after deployments
- Set up alerts for memory usage above 80%
- Document memory requirements in deployment notes

## Related Issues
- OutOfMemoryError is one of the most common CrashLoopBackOff causes
- Similar issues may occur with CPU limits
- Check JVM settings if memory increase doesn't help