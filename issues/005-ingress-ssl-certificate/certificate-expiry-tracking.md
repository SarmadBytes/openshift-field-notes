# SSL Certificate Expiry Tracking

**Last Updated:** October 7, 2025
**Maintained By:** Platform Team

---

## Active Certificates - Expiry Schedule

### Critical Dates

| Cluster | Domain | Expiry Date | Days Remaining | Priority |
|---------|--------|-------------|----------------|----------|
| **DMZ DR** | *.apps.ocp-dmz-dr.example.internal | **October 24, 2025** | **17 days** | 🔴 **CRITICAL** |
| **DMZ PreProd** | *.apps.ocp-dmz.preprod.example.com | **October 29, 2025** | **22 days** | 🟠 **HIGH** |
| **DC46 Internal PreProd** | *.apps.ocp-dc.preprod.example.com | **October 29, 2025** | **22 days** | 🟠 **HIGH** |

---

## Detailed Cluster Information

### 1. DMZ DR Cluster (CRITICAL - Expires Oct 24)
```yaml
Cluster Name: ocp-dmz-dr
Environment: DR (Disaster Recovery)
Domain: *.apps.ocp-dmz-dr.example.internal
API Endpoint: api.ocp-dmz-dr.example.internal
Certificate Expiry: Friday, October 24, 2025 at 2:56:24 PM
Days Until Expiry: 17 days
Renewal Action Required By: October 10, 2025 (14 days buffer)
Status: 🔴 IMMEDIATE ACTION REQUIRED
```

### 2. DMZ PreProd Cluster
```yaml
Cluster Name: ocp-dmz
Environment: PreProduction
Domain: *.apps.ocp-dmz.preprod.example.com
API Endpoint: api.ocp-dmz.preprod.example.com
Certificate Expiry: Wednesday, October 29, 2025 at 3:16:31 PM
Days Until Expiry: 22 days
Renewal Action Required By: October 15, 2025 (14 days buffer)
Status: 🟠 SCHEDULE RENEWAL
```

### 3. DC46 Internal PreProd Cluster
```yaml
Cluster Name: ocp-dc
Environment: Internal PreProduction
Domain: *.apps.ocp-dc.preprod.example.com
API Endpoint: api.ocp-dc.preprod.example.com
Certificate Expiry: Wednesday, October 29, 2025 at 3:17:52 PM
Days Until Expiry: 22 days
Renewal Action Required By: October 15, 2025 (14 days buffer)
Status: 🟠 SCHEDULE RENEWAL
```

---

## Renewal Action Plan

### Immediate Actions (This Week - Oct 7-11, 2025)

#### Priority 1: DMZ DR Cluster
- [ ] Generate CSR for ocp-dmz-dr (Oct 8)
- [ ] Submit certificate request (Oct 8)
- [ ] Follow up on certificate delivery (Oct 10)
- [ ] Schedule maintenance window (Oct 14-16)
- [ ] Apply new certificate (by Oct 16)
- [ ] Verify and test (Oct 16)

#### Priority 2: DMZ PreProd & DC46 Internal
- [ ] Generate CSRs for both clusters (Oct 10)
- [ ] Submit certificate requests (Oct 10)
- [ ] Schedule maintenance windows (Oct 21-23)

### Maintenance Windows

| Date | Time | Cluster | Action |
|------|------|---------|--------|
| Oct 14-16 | TBD | ocp-dmz-dr | Certificate renewal |
| Oct 21-23 | TBD | ocp-dmz.preprod | Certificate renewal |
| Oct 21-23 | TBD | ocp-dc.preprod | Certificate renewal |

---

## Quick Commands for Each Cluster

### DMZ DR Cluster
```bash
# Set environment
export CLUSTER_NAME="ocp-dmz-dr"
export CLUSTER_DOMAIN="ocp-dmz-dr.example.internal"
export APPS_DOMAIN="apps.ocp-dmz-dr.example.internal"
export ENV_NAME="dr"

# Login
oc login --server=https://api.${CLUSTER_DOMAIN}:6443

# Check current certificate
echo | openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 2>/dev/null | openssl x509 -noout -dates
```

### DMZ PreProd Cluster
```bash
# Set environment
export CLUSTER_NAME="ocp-dmz"
export CLUSTER_DOMAIN="ocp-dmz.preprod.example.com"
export APPS_DOMAIN="apps.ocp-dmz.preprod.example.com"
export ENV_NAME="preprod-dmz"

# Login
oc login --server=https://api.${CLUSTER_DOMAIN}:6443

# Check current certificate
echo | openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 2>/dev/null | openssl x509 -noout -dates
```

### DC46 Internal PreProd Cluster
```bash
# Set environment
export CLUSTER_NAME="ocp-dc"
export CLUSTER_DOMAIN="ocp-dc.preprod.example.com"
export APPS_DOMAIN="apps.ocp-dc.preprod.example.com"
export ENV_NAME="preprod-dc1"

# Login
oc login --server=https://api.${CLUSTER_DOMAIN}:6443

# Check current certificate
echo | openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 2>/dev/null | openssl x509 -noout -dates
```

---

## Certificate Renewal Checklist Template

### Pre-Renewal (Per Cluster)
- [ ] Current certificate expiry verified
- [ ] Maintenance window scheduled
- [ ] Stakeholders notified
- [ ] CSR generated with correct domains
- [ ] Private key backed up
- [ ] Certificate request submitted
- [ ] Request ID documented: ___________

### Renewal Day (Per Cluster)
- [ ] Certificate received from CA
- [ ] Certificate chain validated
- [ ] Key-certificate match verified
- [ ] Current configuration backed up
- [ ] Secret created in OpenShift
- [ ] Ingress controller updated
- [ ] Router pods restarted
- [ ] Console access verified
- [ ] Application routes tested

### Post-Renewal (Per Cluster)
- [ ] New expiry date documented
- [ ] Monitoring alerts updated
- [ ] Documentation updated
- [ ] Next renewal scheduled
- [ ] Lessons learned documented

---

## Monitoring Script

Save as `monitor_all_certs.sh`:

```bash
#!/bin/bash

# Certificate monitoring for all clusters
CLUSTERS=(
  "console-openshift-console.apps.ocp-dmz-dr.example.internal"
  "console-openshift-console.apps.ocp-dmz.preprod.example.com"
  "console-openshift-console.apps.ocp-dc.preprod.example.com"
)

echo "=== SSL Certificate Status Report ==="
echo "Date: $(date)"
echo "====================================="

for CLUSTER in "${CLUSTERS[@]}"; do
  echo ""
  echo "Cluster: $CLUSTER"
  EXPIRY=$(echo | openssl s_client -connect ${CLUSTER}:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

  if [[ -n "$EXPIRY" ]]; then
    EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s 2>/dev/null)
    TODAY_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $TODAY_EPOCH) / 86400 ))

    if [[ $DAYS_LEFT -lt 30 ]]; then
      echo "  ⚠️  WARNING: Expires in $DAYS_LEFT days ($EXPIRY)"
    else
      echo "  ✅ OK: Valid for $DAYS_LEFT days ($EXPIRY)"
    fi
  else
    echo "  ❌ ERROR: Could not retrieve certificate"
  fi
done

echo ""
echo "====================================="
```

---

## Contact Information

### Certificate Authority
- Portal: [Internal CA Portal]
- Support Email: certificates@example.com
- Support Phone: +xxx-xxx-xxxx

### Platform Team
- Primary Contact: Sarmad Ahsan
- Backup Contact: Asif Ahsan Ahmed
- Team Email: openshift-platform@example.com

### Escalation Path
1. Platform Team Lead
2. Infrastructure Manager
3. Security Team (for certificate issues)

---

## Historical Records

### Previous Renewals
| Cluster | Previous Expiry | Renewal Date | Ticket # | Notes |
|---------|----------------|--------------|----------|-------|
| ocp-dmz-dr | Oct 24, 2024 | Oct 10, 2024 | TKT-1234 | Completed |
| ocp-dmz.preprod | Oct 29, 2024 | Oct 15, 2024 | TKT-1235 | Completed |
| ocp-dc | Oct 29, 2024 | Oct 15, 2024 | TKT-1236 | Completed |

---

## Notes and Reminders

⚠️ **CRITICAL REMINDERS:**
1. DMZ DR cluster certificate expires Oct 24 - MUST renew by Oct 16
2. Both PreProd clusters expire Oct 29 - Schedule renewal for week of Oct 21
3. Always test in PreProd before Production
4. Keep 14-day buffer before actual expiry
5. Certificate generation typically takes 2-3 business days

📅 **Next Review Date:** October 14, 2025

---

**Document Version:** 1.0
**Last Modified:** October 7, 2025
**Next Update Required:** After DMZ DR renewal (Oct 16, 2025)