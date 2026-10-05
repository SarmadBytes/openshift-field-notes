# Quick Wins - Pod Issues

## CrashLoopBackOff - Memory Issue
**Fix**: `oc set resources deployment/NAME --limits=memory=512Mi --requests=memory=256Mi`  
**When to use**: When logs show OutOfMemoryError or container exits quickly

## ImagePullBackOff - Missing Secret
**Fix**: `oc create secret docker-registry pull-secret --docker-server=REGISTRY --docker-username=USER --docker-password=PASS && oc secrets link default pull-secret --for=pull`  
**When to use**: When pod can't pull private registry images

## CreateContainerConfigError - ConfigMap Missing
**Fix**: `oc get configmap` to verify, then create missing configmap  
**When to use**: When pod references non-existent configmap

## Permission Denied - SCC Issue
**Fix**: `oc adm policy add-scc-to-user anyuid -z default`  
**When to use**: When container needs to run as specific user ID

## Pod Pending - Insufficient Resources
**Fix**: `oc describe nodes` to check resources, then scale down other apps or add nodes  
**When to use**: When pod stuck in Pending status

## Init Container Failing
**Fix**: `oc logs POD_NAME -c INIT_CONTAINER_NAME` to debug, often permission or network issues  
**When to use**: When pod has init containers that keep failing

## Pod Evicted - Node Pressure
**Fix**: `oc delete pods --field-selector status.phase=Failed` to clean up evicted pods  
**When to use**: When seeing many evicted pods

## Container Not Starting - Wrong Command
**Fix**: `oc edit deployment NAME` and check command/args syntax  
**When to use**: When container exits immediately with code 0