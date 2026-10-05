# Complete Guide: OpenShift Default Ingress SSL Certificate Update

**Issue #005**
**Component:** OpenShift Ingress Controller
**Version:** OpenShift 4.x
**Impact:** Cluster-wide

---

## Executive Summary

This guide provides step-by-step instructions to replace the default self-signed SSL certificate in OpenShift's ingress controller with a proper CA-signed certificate. This process affects all routes in the cluster that don't have their own custom certificates.

---

## Table of Contents

1. [Understanding OpenShift Ingress Certificates](#understanding-openshift-ingress-certificates)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Certificate Generation](#phase-1-certificate-generation)
4. [Phase 2: Certificate Request & Processing](#phase-2-certificate-request--processing)
5. [Phase 3: OpenShift Implementation](#phase-3-openshift-implementation)
6. [Phase 4: Verification & Testing](#phase-4-verification--testing)
7. [Troubleshooting Guide](#troubleshooting-guide)
8. [Rollback Procedures](#rollback-procedures)
9. [Automation Scripts](#automation-scripts)
10. [Best Practices](#best-practices)

---

## Understanding OpenShift Ingress Certificates

### What is the Default Ingress Certificate?

The default ingress certificate is used by the OpenShift Router for:
- All routes that don't specify their own certificate
- The OpenShift Console
- OAuth endpoints
- Default application routes

### Certificate Hierarchy

```
Root CA Certificate
    └── Intermediate CA Certificate
            └── Server Certificate (*.apps.cluster.domain)
                    └── Applied to all routes
```

### Why Replace the Default Certificate?

- **Security Compliance:** Self-signed certificates don't meet enterprise security standards
- **User Experience:** Eliminates browser security warnings
- **Trust:** Applications appear more professional with valid certificates
- **Integration:** Required for integration with enterprise systems

---

## Prerequisites

### Required Tools

```bash
# Check required tools
command -v openssl >/dev/null 2>&1 || { echo "openssl required"; exit 1; }
command -v oc >/dev/null 2>&1 || { echo "oc cli required"; exit 1; }

# Verify OpenSSL version (should be 1.1.1 or higher)
openssl version
```

### Required Access

- **OpenShift Cluster Admin:** Required to modify ingress controller
- **Certificate Authority Access:** To request certificates
- **DNS Verification:** Ability to verify domain ownership if required

### Information Gathering

```bash
# Get cluster information
oc whoami --show-server
oc get clusterversion
oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'

# Current ingress certificate info
oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate}'
```

---

## Phase 1: Certificate Generation

### Step 1.1: Prepare Environment

```bash
#!/bin/bash
# Setup working directory
export WORK_DIR="${HOME}/ocp-ssl-update"
mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# Define environment
echo "Select environment:"
echo "1) Development"
echo "2) Test"
echo "3) PreProduction"
echo "4) Production"
read -p "Enter choice [1-4]: " ENV_CHOICE

case $ENV_CHOICE in
  1) export ENV_NAME="dev" ;;
  2) export ENV_NAME="test" ;;
  3) export ENV_NAME="preprod" ;;
  4) export ENV_NAME="prod" ;;
  *) echo "Invalid choice"; exit 1 ;;
esac

# Set variables
export CLUSTER_NAME="ocp"
export DOMAIN="example.com"
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${ENV_NAME}.${DOMAIN}"
export APPS_DOMAIN="apps.${CLUSTER_DOMAIN}"
export DATE_STAMP=$(date +%Y%m%d)

echo "=== Configuration ==="
echo "Environment: ${ENV_NAME}"
echo "Cluster Domain: ${CLUSTER_DOMAIN}"
echo "Apps Domain: ${APPS_DOMAIN}"
echo "Working Directory: ${WORK_DIR}"
echo "===================="
```

### Step 1.2: Create OpenSSL Configuration

```bash
# Generate comprehensive OpenSSL config
cat > openssl_${ENV_NAME}.cnf <<EOF
# OpenSSL Configuration for ${ENV_NAME} Environment
# Generated: $(date)

[ req ]
default_bits       = 2048
default_md         = sha256
distinguished_name = req_distinguished_name
req_extensions     = v3_req
prompt            = no

[ req_distinguished_name ]
C                 = SA
ST                = Region
L                 = City
O                 = Organization Name
OU                = OpenShift Platform Team
CN                = *.${APPS_DOMAIN}
emailAddress      = openshift-team@${DOMAIN}

[ v3_req ]
basicConstraints     = CA:FALSE
keyUsage            = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName      = @alt_names

[ alt_names ]
DNS.1 = *.${APPS_DOMAIN}
DNS.2 = ${APPS_DOMAIN}
DNS.3 = *.apps.${CLUSTER_DOMAIN}
DNS.4 = api.${CLUSTER_DOMAIN}
DNS.5 = api-int.${CLUSTER_DOMAIN}
DNS.6 = console-openshift-console.${APPS_DOMAIN}
DNS.7 = oauth-openshift.${APPS_DOMAIN}
EOF

echo "Configuration file created: openssl_${ENV_NAME}.cnf"
```

### Step 1.3: Generate Private Key and CSR

```bash
# Generate private key (2048 or 4096 bits)
openssl genrsa -out ${ENV_NAME}-ingress.key 2048

# Set proper permissions
chmod 600 ${ENV_NAME}-ingress.key

# Create backup
cp ${ENV_NAME}-ingress.key ${ENV_NAME}-ingress.key.backup-${DATE_STAMP}

# Generate CSR
openssl req -new \
  -key ${ENV_NAME}-ingress.key \
  -out ${ENV_NAME}-ingress.csr \
  -config openssl_${ENV_NAME}.cnf

# Verify CSR
echo "=== CSR Verification ==="
openssl req -text -noout -verify -in ${ENV_NAME}-ingress.csr | grep -E "Subject:|DNS:"
```

### Step 1.4: Display CSR for Submission

```bash
# Create submission file
cat > certificate_request_${ENV_NAME}.txt <<EOF
==============================================
CERTIFICATE SIGNING REQUEST
==============================================
Environment: ${ENV_NAME}
Domain: *.${APPS_DOMAIN}
Date: $(date)
Requested By: $(whoami)
==============================================

$(cat ${ENV_NAME}-ingress.csr)

==============================================
END OF CSR
==============================================
EOF

echo "CSR saved to: certificate_request_${ENV_NAME}.txt"
```

---

## Phase 2: Certificate Request & Processing

### Step 2.1: Submit Certificate Request

**Manual Process:**
1. Copy CSR from `certificate_request_${ENV_NAME}.txt`
2. Submit to your Certificate Authority
3. Request options:
   - Certificate Type: SSL/TLS Server Certificate
   - Validity: 1-2 years
   - Include full certificate chain
   - Format: Base64 PEM

**Automated (if API available):**
```bash
# Example for internal CA API
curl -X POST https://ca.example.com/api/request \
  -H "Authorization: Bearer $CA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "csr": "$(cat ${ENV_NAME}-ingress.csr | base64 -w0)",
  "validity_years": 2,
  "include_chain": true
}
EOF
```

### Step 2.2: Process Received Certificates

```bash
# After receiving certificates (usually in ZIP)
mkdir -p received_certs_${DATE_STAMP}
cd received_certs_${DATE_STAMP}

# Extract certificates
unzip ../certificate_bundle.zip

# Identify certificate files
ls -la
# Expected files:
# - server.crt or domain.crt (Server certificate)
# - intermediate.crt or ca-bundle.crt (Intermediate CA)
# - root.crt (Root CA - optional)
```

### Step 2.3: Convert and Validate Certificates

```bash
# Convert any DER/Binary certificates to PEM
for cert in *.cer *.der *.crt; do
  if [[ -f "$cert" ]]; then
    # Check if already PEM
    if ! openssl x509 -in "$cert" -text -noout &>/dev/null; then
      echo "Converting $cert from DER to PEM..."
      openssl x509 -inform DER -in "$cert" -out "${cert}.pem"
    else
      echo "$cert is already in PEM format"
      cp "$cert" "${cert}.pem"
    fi
  fi
done

# Examine each certificate
for pem in *.pem; do
  echo "=== Certificate: $pem ==="
  openssl x509 -in $pem -noout -subject -issuer -dates
  echo ""
done
```

### Step 2.4: Create Certificate Chain

```bash
# CRITICAL: Order must be Server → Intermediate → Root
# Create fullchain certificate

# Method 1: If you know the files
cat server.crt.pem > ${ENV_NAME}-fullchain.pem
cat intermediate.crt.pem >> ${ENV_NAME}-fullchain.pem
[[ -f root.crt.pem ]] && cat root.crt.pem >> ${ENV_NAME}-fullchain.pem

# Method 2: Interactive selection
echo "Select certificates in order:"
echo "1. First, select the SERVER certificate (CN=*.apps...)"
echo "2. Then, select the INTERMEDIATE certificate"
echo "3. Finally, select the ROOT certificate (if available)"

# Verify the chain
echo "=== Certificate Chain Verification ==="
openssl verify -CAfile ${ENV_NAME}-fullchain.pem ${ENV_NAME}-fullchain.pem

# Verify certificate matches private key
echo "=== Key Matching Verification ==="
CERT_MOD=$(openssl x509 -noout -modulus -in ${ENV_NAME}-fullchain.pem | openssl md5)
KEY_MOD=$(openssl rsa -noout -modulus -in ../${ENV_NAME}-ingress.key | openssl md5)

if [[ "$CERT_MOD" == "$KEY_MOD" ]]; then
  echo "✓ Certificate and private key match"
else
  echo "✗ ERROR: Certificate and private key do NOT match!"
  exit 1
fi
```

---

## Phase 3: OpenShift Implementation

### Step 3.1: Pre-Implementation Checks

```bash
# Login to OpenShift
oc login --server=https://api.${CLUSTER_DOMAIN}:6443

# Verify cluster
echo "=== Cluster Verification ==="
oc whoami --show-server
oc get nodes | head -5

# Check current ingress configuration
echo "=== Current Ingress Configuration ==="
oc get ingresscontroller default -n openshift-ingress-operator -o yaml | grep -A5 defaultCertificate

# Backup current configuration
mkdir -p backups
oc get ingresscontroller default -n openshift-ingress-operator -o yaml > backups/ingress-controller-${DATE_STAMP}.yaml
oc get secret -n openshift-ingress -o yaml > backups/ingress-secrets-${DATE_STAMP}.yaml
```

### Step 3.2: Create Certificate Secret

```bash
# Delete old secret if exists
oc delete secret custom-ingress-cert -n openshift-ingress --ignore-not-found

# Create new secret with certificate and key
oc create secret tls custom-ingress-cert \
  --cert=received_certs_${DATE_STAMP}/${ENV_NAME}-fullchain.pem \
  --key=${ENV_NAME}-ingress.key \
  -n openshift-ingress \
  --dry-run=client -o yaml | oc apply -f -

# Verify secret
oc get secret custom-ingress-cert -n openshift-ingress
oc get secret custom-ingress-cert -n openshift-ingress -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -dates
```

### Step 3.3: Update Ingress Controller

```bash
# Apply the certificate to ingress controller
oc patch ingresscontroller.operator default \
  -n openshift-ingress-operator \
  --type=merge \
  --patch='{"spec":{"defaultCertificate":{"name":"custom-ingress-cert"}}}'

# Verify patch was applied
oc get ingresscontroller.operator default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate}'
echo ""
```

### Step 3.4: Monitor Rollout

```bash
# Watch router pod rollout
echo "=== Monitoring Router Pod Rollout ==="
oc get pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default

# Wait for rollout to complete
oc rollout status deployment/router-default -n openshift-ingress --timeout=600s

# Verify all pods are running
oc get pods -n openshift-ingress | grep router
```

---

## Phase 4: Verification & Testing

### Step 4.1: Internal Verification

```bash
# Get a router pod
ROUTER_POD=$(oc get pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default -o jsonpath='{.items[0].metadata.name}')

# Check certificate inside pod
echo "=== Certificate in Router Pod ==="
oc exec -n openshift-ingress ${ROUTER_POD} -- openssl x509 -in /etc/pki/tls/private/tls-certs/tls.crt -noout -subject -dates
```

### Step 4.2: External Verification

```bash
# Test from command line
echo "=== Testing Console Route ==="
echo | openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 -servername console-openshift-console.${APPS_DOMAIN} 2>/dev/null | openssl x509 -noout -text | grep -A2 "Subject:"

# Test multiple endpoints
for endpoint in console-openshift-console oauth-openshift prometheus-k8s-openshift-monitoring grafana-openshift-monitoring; do
  echo "Testing: ${endpoint}.${APPS_DOMAIN}"
  curl -ILs https://${endpoint}.${APPS_DOMAIN} | head -1
done
```

### Step 4.3: Browser Verification

1. Open: `https://console-openshift-console.apps.${CLUSTER_DOMAIN}`
2. Check for padlock icon (no warnings)
3. Click padlock → Certificate details
4. Verify:
   - Issued to: `*.apps.${CLUSTER_DOMAIN}`
   - Issued by: Your CA
   - Valid from/to: Check dates

### Step 4.4: Comprehensive Test Script

```bash
cat > test_certificate.sh <<'SCRIPT'
#!/bin/bash
APPS_DOMAIN=$1

if [[ -z "$APPS_DOMAIN" ]]; then
  echo "Usage: $0 <apps-domain>"
  exit 1
fi

echo "=== SSL Certificate Test Report ==="
echo "Domain: ${APPS_DOMAIN}"
echo "Date: $(date)"
echo "===================================="

# Test console
echo -e "\n[Console Test]"
timeout 5 openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 </dev/null 2>/dev/null | grep -E "subject=|issuer=|Verify return code"

# Test OAuth
echo -e "\n[OAuth Test]"
timeout 5 openssl s_client -connect oauth-openshift.${APPS_DOMAIN}:443 </dev/null 2>/dev/null | grep -E "subject=|issuer=|Verify return code"

# Check expiry
echo -e "\n[Certificate Expiry]"
echo | openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 2>/dev/null | openssl x509 -noout -dates

echo -e "\n=== Test Complete ==="
SCRIPT

chmod +x test_certificate.sh
./test_certificate.sh ${APPS_DOMAIN}
```

---

## Troubleshooting Guide

### Problem: Certificate Not Applied

```bash
# Check operator logs
oc logs -n openshift-ingress-operator deployment/ingress-operator --tail=50 | grep -i error

# Check ingress controller status
oc describe ingresscontroller default -n openshift-ingress-operator | grep -A20 "Status:"

# Verify secret exists
oc get secret custom-ingress-cert -n openshift-ingress -o yaml | grep -A5 "data:"
```

### Problem: Certificate Chain Issues

```bash
# Verify certificate chain order
openssl verify -verbose -CAfile intermediate.pem server.pem

# Check for chain completeness
openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 -showcerts </dev/null 2>/dev/null | grep -E "s:|i:"
```

### Problem: Pods in CrashLoopBackOff

```bash
# Check pod logs
oc logs -n openshift-ingress router-default-xxxxx --previous

# Common issues:
# - Certificate format error
# - Private key mismatch
# - File permissions

# Force recreation
oc delete pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default
```

### Problem: Some Routes Still Show Old Certificate

```bash
# Routes with edge termination use their own certificates
oc get routes --all-namespaces -o json | jq -r '.items[] | select(.spec.tls.termination == "edge") | "\(.metadata.namespace)/\(.metadata.name)"'

# These routes need individual updates
```

---

## Rollback Procedures

### Immediate Rollback

```bash
# Remove custom certificate configuration
oc patch ingresscontroller.operator default \
  -n openshift-ingress-operator \
  --type=json \
  --patch='[{"op": "remove", "path": "/spec/defaultCertificate"}]'

# Monitor rollback
oc rollout status deployment/router-default -n openshift-ingress
```

### Restore from Backup

```bash
# Restore previous configuration
oc apply -f backups/ingress-controller-${DATE_STAMP}.yaml

# Verify restoration
oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate}'
```

---

## Automation Scripts

### Complete Automation Script

```bash
cat > update_ingress_certificate.sh <<'EOF'
#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function definitions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Main execution
main() {
    local ENV_NAME=$1
    local CERT_FILE=$2
    local KEY_FILE=$3

    if [[ $# -ne 3 ]]; then
        echo "Usage: $0 <environment> <certificate-file> <key-file>"
        echo "Example: $0 dev fullchain.pem private.key"
        exit 1
    fi

    log_info "Starting certificate update for $ENV_NAME environment"

    # Verify files
    [[ ! -f "$CERT_FILE" ]] && { log_error "Certificate file not found: $CERT_FILE"; exit 1; }
    [[ ! -f "$KEY_FILE" ]] && { log_error "Key file not found: $KEY_FILE"; exit 1; }

    # Verify certificate and key match
    log_info "Verifying certificate and key match..."
    CERT_MOD=$(openssl x509 -noout -modulus -in "$CERT_FILE" | openssl md5)
    KEY_MOD=$(openssl rsa -noout -modulus -in "$KEY_FILE" | openssl md5)

    if [[ "$CERT_MOD" != "$KEY_MOD" ]]; then
        log_error "Certificate and key do not match!"
        exit 1
    fi
    log_info "Certificate and key match verified ✓"

    # Check OpenShift login
    log_info "Checking OpenShift connection..."
    oc whoami &>/dev/null || { log_error "Not logged in to OpenShift"; exit 1; }

    # Backup current configuration
    log_info "Creating backup..."
    BACKUP_FILE="backup-ingress-$(date +%Y%m%d-%H%M%S).yaml"
    oc get ingresscontroller default -n openshift-ingress-operator -o yaml > "$BACKUP_FILE"
    log_info "Backup saved to: $BACKUP_FILE"

    # Create/update secret
    log_info "Creating certificate secret..."
    oc delete secret custom-ingress-cert -n openshift-ingress --ignore-not-found
    oc create secret tls custom-ingress-cert \
        --cert="$CERT_FILE" \
        --key="$KEY_FILE" \
        -n openshift-ingress

    # Update ingress controller
    log_info "Updating ingress controller..."
    oc patch ingresscontroller.operator default \
        -n openshift-ingress-operator \
        --type=merge \
        --patch='{"spec":{"defaultCertificate":{"name":"custom-ingress-cert"}}}'

    # Wait for rollout
    log_info "Waiting for router pods to restart..."
    oc rollout status deployment/router-default -n openshift-ingress --timeout=600s

    log_info "Certificate update completed successfully!"
    log_info "Verify at: https://console-openshift-console.apps.ocp.${ENV_NAME}.example.com"
}

# Run main function
main "$@"
EOF

chmod +x update_ingress_certificate.sh
```

---

## Best Practices

### Certificate Management

1. **Certificate Lifecycle:**
   - Track expiry dates in calendar
   - Renew 30 days before expiry
   - Keep certificate history for audit

2. **Security:**
   - Never commit private keys to git
   - Use secrets management tools
   - Rotate keys with each renewal

3. **Documentation:**
   - Document certificate details
   - Maintain runbooks
   - Record vendor ticket numbers

### Operational Practices

1. **Testing:**
   - Always test in non-production first
   - Verify all endpoints after update
   - Have rollback plan ready

2. **Communication:**
   - Schedule maintenance windows
   - Notify stakeholders
   - Document in change management

3. **Monitoring:**
   - Set up certificate expiry alerts
   - Monitor after deployment
   - Check application functionality

---

## Certificate Expiry Monitoring

```bash
# Create monitoring script
cat > check_cert_expiry.sh <<'EOF'
#!/bin/bash
DAYS_WARNING=30
DOMAIN=$1

EXPIRY=$(echo | openssl s_client -connect ${DOMAIN}:443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s)
TODAY_EPOCH=$(date +%s)
DAYS_LEFT=$(( ($EXPIRY_EPOCH - $TODAY_EPOCH) / 86400 ))

if [[ $DAYS_LEFT -lt $DAYS_WARNING ]]; then
  echo "WARNING: Certificate expires in $DAYS_LEFT days"
  exit 1
else
  echo "OK: Certificate valid for $DAYS_LEFT more days"
  exit 0
fi
EOF

chmod +x check_cert_expiry.sh
```

---

## Summary Checklist

### Pre-Implementation
- [ ] Environment variables set
- [ ] OpenSSL configuration created
- [ ] CSR generated
- [ ] Private key backed up
- [ ] Certificate request submitted

### Implementation
- [ ] Certificate received and processed
- [ ] Certificate chain created correctly
- [ ] Certificate matches private key
- [ ] Secret created in OpenShift
- [ ] Ingress controller patched
- [ ] Router pods restarted

### Post-Implementation
- [ ] Console accessible without warnings
- [ ] OAuth endpoint working
- [ ] Sample applications tested
- [ ] Certificate expiry documented
- [ ] Monitoring configured
- [ ] Documentation updated

---

**Last Updated:** October 2025
**Tested on:** OpenShift 4.12, 4.13, 4.14, 4.15
**Author:** OpenShift Platform Team
**Current Focus:** DC46 PreProd Cluster (ocp-dc.preprod.example.com)