# OpenShift Field Notes

Real OpenShift problems from production work in regulated environments (banking, telecom) — and exactly how they were fixed.
Every note follows the same shape: **symptom → root cause → fix → how to prevent it**. Hostnames, IPs and client details are replaced with neutral examples.

Maintained by **Sarmad Ahsan**, OpenShift consultant. New notes are added regularly.

## Index
| # | Note | Area | OCP |
|---|---|---|---|
| 001 | [Pod stuck in CrashLoopBackOff](issues/001-pod-crashloop/) | Workloads | 4.x |
| 002 | [Service-account token generation after the 4.17 upgrade](issues/002-service-account-token-4.17/) | Upgrades · Auth | 4.17 |
| 003 | [vSphere storage permission issues](issues/003-vsphere-permissions/) | Storage · vSphere | 4.17 |
| 004 | [Node.js app "permission denied" on write under restricted-v2 SCC](issues/004-nodejs-permission-denied/) | Security · SCC | 4.x |
| 005 | [Replacing the default ingress TLS certificate (+ expiry tracking)](issues/005-ingress-ssl-certificate/) | Certificates · Ingress | 4.x |
| 006 | [Extending a node's root disk (120 GB → 220 GB)](issues/006-extend-node-root-disk/) | Nodes · Storage | 4.x |
| 007 | [Rebooting a node gracefully (cordon, drain, verify)](issues/007-graceful-node-reboot/) | Nodes · Day-2 | 4.x |

Also: [quick wins for pod issues](quick-wins/pod-issues.md) · [debugging commands](commands/debugging.md) · [note template](templates/issue-template.md)

## Safety
These notes come from real clusters, but every environment is different. Read each command before you run it, test outside production first, and never run `oc delete` or force operations without a rollback plan.

## Licence
MIT — use, copy and adapt freely; a link back is appreciated.
