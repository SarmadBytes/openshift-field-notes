# SSL Certificate Renewal Runbook

**Purpose:** Step-by-step guide for renewing SSL certificates across all OpenShift clusters
**Updated:** October 7, 2025

---

## ⚠️ URGENT RENEWALS REQUIRED

### Timeline
- **Oct 24, 2025**: DMZ DR expires (17 days) - CRITICAL
- **Oct 29, 2025**: DMZ PreProd & DC46 Internal expire (22 days) - HIGH

---

## Renewal Execution Plan

### Week 1: October 7-11, 2025 (THIS WEEK)

#### Monday, Oct 7 (TODAY)
- [x] Document current certificate status
- [ ] Notify stakeholders about upcoming renewals
- [ ] Schedule maintenance windows

#### Tuesday, Oct 8
**DMZ DR Cluster - CSR Generation**
```bash
# 1. Load configuration
source ~/openshift-field-notes/issues/005-ingress-ssl-certificate/cluster-configs/dmz-dr-config.sh

# 2. Generate CSR
cd ${WORK_DIR}
generate_csr

# 3. Submit certificate request
cat ${CERT_PREFIX}.csr
# Copy and submit to CA portal
```

#### Wednesday, Oct 9
**PreProd Clusters - CSR Generation**
```bash
# DMZ PreProd
source ~/openshift-field-notes/issues/005-ingress-ssl-certificate/cluster-configs/dmz-preprod-config.sh
generate_csr

# DC46 Internal PreProd
source ~/openshift-field-notes/issues/005-ingress-ssl-certificate/cluster-configs/dc1-internal-preprod-config.sh
generate_csr
```

#### Thursday, Oct 10
- [ ] Follow up on DMZ DR certificate request
- [ ] Submit PreProd certificate requests
- [ ] Document request IDs

#### Friday, Oct 11
- [ ] Verify certificate delivery for DMZ DR
- [ ] Prepare for next week's implementations

---

### Week 2: October 14-18, 2025

#### Monday, Oct 14 - DMZ DR Implementation

**Pre-Implementation (9:00 AM)**
```bash
# 1. Login to cluster
oc login --server=https://api.ocp-dmz-dr.example.internal:6443

# 2. Backup current configuration
mkdir -p ~/backups/dmz-dr
oc get ingresscontroller default -n openshift-ingress-operator -o yaml > ~/backups/dmz-dr/ingress-backup-$(date +%Y%m%d).yaml

# 3. Check current certificate
echo | openssl s_client -connect console-openshift-console.apps.ocp-dmz-dr.example.internal:443 2>/dev/null | openssl x509 -noout -dates
```

**Implementation (10:00 AM)**
```bash
# 1. Process received certificate
cd ~/ssl-renewal/dmz-dr
cat server.pem intermediate.pem root.pem > fullchain.pem

# 2. Verify certificate
openssl x509 -noout -modulus -in fullchain.pem | openssl md5
openssl rsa -noout -modulus -in ocp-dmz-dr-*.key | openssl md5

# 3. Apply to cluster
oc create secret tls custom-ingress-cert \
  --cert=fullchain.pem \
  --key=ocp-dmz-dr-*.key \
  -n openshift-ingress \
  --dry-run=client -o yaml | oc apply -f -

oc patch ingresscontroller.operator default \
  -n openshift-ingress-operator \
  --type=merge \
  --patch='{"spec":{"defaultCertificate":{"name":"custom-ingress-cert"}}}'

# 4. Monitor rollout
oc rollout status deployment/router-default -n openshift-ingress
```

**Verification (11:00 AM)**
```bash
# Test new certificate
./test_certificate.sh apps.ocp-dmz-dr.example.internal
```

---

### Week 3: October 21-25, 2025

#### Tuesday, Oct 21 - DMZ PreProd Implementation

```bash
# Load config and implement
source ~/openshift-field-notes/issues/005-ingress-ssl-certificate/cluster-configs/dmz-preprod-config.sh

# Follow same process as DMZ DR
# ... (implementation steps)
```

#### Wednesday, Oct 22 - DC46 Internal PreProd Implementation

```bash
# Load config and implement
source ~/openshift-field-notes/issues/005-ingress-ssl-certificate/cluster-configs/dc1-internal-preprod-config.sh

# Follow same process as DMZ DR
# ... (implementation steps)
```

---

## Quick Rollback Procedure

If issues occur during renewal:

```bash
# 1. Remove custom certificate
oc patch ingresscontroller.operator default \
  -n openshift-ingress-operator \
  --type=json \
  --patch='[{"op": "remove", "path": "/spec/defaultCertificate"}]'

# 2. Wait for rollback
oc rollout status deployment/router-default -n openshift-ingress

# 3. Verify rollback
echo | openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 2>/dev/null | openssl x509 -noout -dates
```

---

## Communication Templates

### Maintenance Announcement
```
Subject: OpenShift Certificate Renewal - [CLUSTER NAME]

Team,

We will be renewing the SSL certificate for the [CLUSTER NAME] cluster.

Details:
- Cluster: [CLUSTER NAME]
- Date: [DATE]
- Time: [TIME]
- Duration: 30 minutes
- Impact: Brief router restart, no application downtime expected

Please contact the platform team if you have concerns.

Regards,
OpenShift Platform Team
```

### Completion Notification
```
Subject: Certificate Renewal Complete - [CLUSTER NAME]

Team,

The SSL certificate renewal for [CLUSTER NAME] has been completed successfully.

- New certificate valid until: [DATE]
- All services verified and operational
- No issues reported

Thank you for your patience.

Regards,
OpenShift Platform Team
```

---

## Verification Checklist

### Per Cluster Verification
- [ ] Console accessible without warnings
- [ ] OAuth endpoint functional
- [ ] Certificate shows correct expiry date
- [ ] No browser security warnings
- [ ] Application routes working
- [ ] Monitoring/logging functional

### Test Commands
```bash
# Quick verification script
for cluster in "ocp-dmz-dr.ad" "ocp-dmz.preprod" "ocp-dc.preprod"; do
  echo "Testing $cluster..."
  echo | openssl s_client -connect console-openshift-console.apps.${cluster}.example.com:443 2>/dev/null | openssl x509 -noout -subject -dates
  echo "---"
done
```

---

## Contact List

### During Renewal

| Role | Name | Contact | Availability |
|------|------|---------|--------------|
| Lead | Sarmad Ahsan | +xxx-xxx-xxxx | Primary |
| Backup | Asif Ahsan Ahmed | +xxx-xxx-xxxx | If lead unavailable |
| CA Support | Certificate Team | certificates@example.com | Business hours |
| Escalation | Platform Manager | +xxx-xxx-xxxx | Emergency only |

---

## Post-Renewal Tasks

After each cluster renewal:

1. **Update Documentation**
   ```bash
   # Update expiry tracking
   vi ~/openshift-field-notes/issues/005-ingress-ssl-certificate/certificate-expiry-tracking.md
   ```

2. **Set Calendar Reminders**
   - Next expiry date minus 30 days
   - Next expiry date minus 14 days
   - Next expiry date minus 7 days

3. **Update Monitoring**
   ```bash
   # Update monitoring script with new dates
   vi ~/monitoring/cert-expiry-check.sh
   ```

4. **Archive Old Certificates**
   ```bash
   # Move old certs to archive
   mv ~/ssl-renewal/*/old-*.pem ~/ssl-renewal/archive/
   ```

---

## Lessons Learned Log

### October 2025 Renewal Cycle
- **Issue**: [Document any issues]
- **Resolution**: [How it was resolved]
- **Prevention**: [How to prevent next time]

---

**End of Runbook**