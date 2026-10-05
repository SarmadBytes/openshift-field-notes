# Problem: Pod Stuck in CrashLoopBackOff

## Environment
- OpenShift Version: 4.10
- Namespace: production-app
- Component: Application pod
- When it occurred: After new deployment

## Description
Application pod was continuously restarting with CrashLoopBackOff status. The application would start, run for about 30 seconds, then crash and restart.

## Symptoms
- Pod status showing "CrashLoopBackOff"
- Restart count increasing every minute
- Application not accessible
- Health checks failing

## Impact
- Application unavailable to users
- Automated alerts firing
- Team blocked from further deployments