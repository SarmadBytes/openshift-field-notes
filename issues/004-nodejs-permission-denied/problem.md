# Problem: Node.js Application Permission Denied on File Write

## Environment
- OpenShift Version: 4.x
- Environment: DMZ PreProd
- Namespace: nmp-web-preprod
- Component: Node.js application pod
- Service Account: merchant-portal-icashpro
- Base Image: registry.access.redhat.com/ubi9/nodejs-20:1
- When it occurred: During application deployment via GitLab CI/CD

## Description

A Node.js application deployed through GitLab service account fails to start in DMZ PreProd environment with permission denied error when trying to write to `./web-content/env.js` file. The application attempts to write environment configuration at startup but lacks permissions to modify the file.

## Symptoms

- Pod starts but crashes immediately with EACCES error
- Error occurs during server.js initialization (line 59)
- Application tries to write to `./web-content/env.js` at runtime
- Same deployment works fine in DEV environment
- Issue only occurs in DMZ PreProd environment

## Impact

- Application fails to start
- Complete service outage in PreProd DMZ
- Blocks deployment pipeline from GitLab
- Prevents testing in PreProd environment

## Environment Differences

- **DEV Environment**: Working correctly
- **DMZ PreProd Environment**: Failing with permission error
- Suggests environmental configuration or SCC (SecurityContextConstraints) differences between environments