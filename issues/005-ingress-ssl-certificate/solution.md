# Solution: Update Default Ingress SSL Certificate in OpenShift 4.x

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Step 1: Generate CSR and Private Key](#step-1-generate-csr-and-private-key)
3. [Step 2: Submit Certificate Request](#step-2-submit-certificate-request)
4. [Step 3: Process Certificate Chain](#step-3-process-certificate-chain)
5. [Step 4: Create Certificate Secret](#step-4-create-certificate-secret)
6. [Step 5: Update Ingress Controller](#step-5-update-ingress-controller)
7. [Step 6: Verification](#step-6-verification)
8. [Troubleshooting](#troubleshooting)
9. [Rollback Procedure](#rollback-procedure)

---

## Prerequisites

### Required Access
- OpenShift cluster admin privileges
- Access to certificate request portal
- OpenSSL installed on workstation

### Required Information
- Cluster domain name (e.g., `ocp.dev.example.com`)
- Apps domain name (e.g., `*.apps.ocp.dev.example.com`)
- Organization details for certificate

### Environment Variables (Set these first)
```bash
# Set your environment
export ENV_NAME="dev"                                    # Change to: dev, test, preprod, prod
export CLUSTER_DOMAIN="ocp.${ENV_NAME}.example.com"
export APPS_DOMAIN="apps.${CLUSTER_DOMAIN}"
export CERT_PREFIX="ocp-${ENV_NAME}"
```

---

## Step 1: Generate CSR and Private Key

### 1.1 Create OpenSSL Configuration File

Create configuration file with SAN (Subject Alternative Names):

```bash
cat > openssl_san_${CERT_PREFIX}.cnf <<EOF
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no
default_md = sha256

[ req_distinguished_name ]
C = SA
ST = RI
L = City
O = YourOrganization
OU = OpenShift Platform
CN = *.${APPS_DOMAIN}
emailAddress = openshift@example.com

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.${APPS_DOMAIN}
DNS.2 = ${APPS_DOMAIN}
DNS.3 = *.${CLUSTER_DOMAIN}
EOF
```

### 1.2 Generate CSR and Private Key

```bash
# Generate CSR and private key
openssl req -new \
  -out ${CERT_PREFIX}.csr \
  -newkey rsa:2048 \
  -nodes \
  -sha256 \
  -keyout ${CERT_PREFIX}.key \
  -config openssl_san_${CERT_PREFIX}.cnf

# Verify CSR details
openssl req -text -noout -verify -in ${CERT_PREFIX}.csr

# Save private key securely (you'll need this later!)
cp ${CERT_PREFIX}.key ${CERT_PREFIX}.key.backup
```

### 1.3 Display CSR for Certificate Request

```bash
# Display CSR content for copying
echo "========== CSR CONTENT =========="
cat ${CERT_PREFIX}.csr
echo "========== END CSR =========="
```

---

## Step 2: Submit Certificate Request

### 2.1 Submit to Certificate Authority

1. Copy the CSR content from above
2. Submit certificate request through your organization's process
3. Request certificate WITH full chain
4. Save request ID for tracking

### 2.2 Certificate Request Details

When submitting request, provide:
- **Certificate Type**: SSL/TLS Server Certificate
- **Validity Period**: 1-2 years (as per policy)
- **Domain**: `*.apps.ocp.${ENV_NAME}.example.com`
- **SAN Entries**: As configured in CSR
- **Key Size**: 2048 bits
- **Signature Algorithm**: SHA-256

---

## Step 3: Process Certificate Chain

### 3.1 Extract Certificates from Response

Once you receive the certificate bundle (usually ZIP file):

```bash
# Create working directory
mkdir -p ${CERT_PREFIX}-certs
cd ${CERT_PREFIX}-certs

# Extract ZIP file (if provided as ZIP)
unzip certificate-bundle.zip

# You should have these files:
# - Server certificate
# - Intermediate certificate(s)
# - Root CA certificate (optional)
```

### 3.2 Convert to PEM Format (if needed)

```bash
# If certificates are in DER/CER format, convert to PEM
for cert in *.cer; do
  openssl x509 -inform DER -in $cert -out ${cert%.cer}.pem
done

# If certificates are in P7B format
openssl pkcs7 -print_certs -in certificate.p7b -out certificate.pem
```

### 3.3 Create Certificate Chain File

**IMPORTANT**: Order matters! Must be: Server → Intermediate → Root

```bash
# Method 1: Manual ordering
cat server-certificate.pem > ${CERT_PREFIX}-chain.pem
cat intermediate-certificate.pem >> ${CERT_PREFIX}-chain.pem
cat root-certificate.pem >> ${CERT_PREFIX}-chain.pem  # Optional

# Method 2: If you have separate files
cat ${CERT_PREFIX}.pem > ${CERT_PREFIX}-fullchain.pem
cat intermediate.pem >> ${CERT_PREFIX}-fullchain.pem
cat root.pem >> ${CERT_PREFIX}-fullchain.pem  # Optional

# Verify certificate chain
openssl verify -CAfile ${CERT_PREFIX}-fullchain.pem ${CERT_PREFIX}.pem
```

### 3.4 Verify Certificate Details

```bash
# Check certificate details
openssl x509 -in ${CERT_PREFIX}-fullchain.pem -text -noout | head -20

# Verify certificate matches private key
openssl x509 -noout -modulus -in ${CERT_PREFIX}-fullchain.pem | openssl md5
openssl rsa -noout -modulus -in ${CERT_PREFIX}.key | openssl md5
# Both MD5 hashes should match!

# Check certificate expiry
openssl x509 -in ${CERT_PREFIX}-fullchain.pem -noout -dates
```

---

## Step 4: Create Certificate Secret

### 4.1 Login to OpenShift

```bash
# Login to cluster
oc login --server=https://api.${CLUSTER_DOMAIN}:6443

# Verify you're on correct cluster
oc whoami --show-server
```

### 4.2 Create Secret in openshift-ingress Namespace

```bash
# Create secret with certificate and key
oc create secret tls custom-ingress-cert \
  --cert=${CERT_PREFIX}-fullchain.pem \
  --key=${CERT_PREFIX}.key \
  -n openshift-ingress

# Verify secret created
oc get secret custom-ingress-cert -n openshift-ingress
oc describe secret custom-ingress-cert -n openshift-ingress
```

### 4.3 Backup Current Configuration

```bash
# Backup current ingress configuration
oc get ingresscontroller default -n openshift-ingress-operator -o yaml > ingress-backup-$(date +%Y%m%d).yaml

# Check current certificate
oc get secret router-certs-default -n openshift-ingress -o yaml > router-certs-backup-$(date +%Y%m%d).yaml
```

---

## Step 5: Update Ingress Controller

### 5.1 Patch Ingress Controller

```bash
# Update default ingress controller to use custom certificate
oc patch ingresscontroller.operator default \
  -n openshift-ingress-operator \
  --type=merge \
  --patch='{"spec":{"defaultCertificate":{"name":"custom-ingress-cert"}}}'

# Verify patch applied
oc get ingresscontroller.operator default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate}'
```

### 5.2 Monitor Rollout

```bash
# Watch ingress pods restart
oc get pods -n openshift-ingress -w

# Check rollout status
oc rollout status deployment/router-default -n openshift-ingress

# Verify all pods are running
oc get pods -n openshift-ingress
```

---

## Step 6: Verification

### 6.1 Verify Certificate via OpenSSL

```bash
# Check certificate on router pods
ROUTER_POD=$(oc get pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default -o jsonpath='{.items[0].metadata.name}')

# Verify certificate inside pod
oc exec -n openshift-ingress $ROUTER_POD -- openssl x509 -in /etc/pki/tls/private/tls-certs/tls.crt -text -noout | grep Subject:

# Test from outside cluster
echo | openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 -servername console-openshift-console.${APPS_DOMAIN} 2>/dev/null | openssl x509 -noout -subject -dates
```

### 6.2 Verify via Browser

1. Open browser to: `https://console-openshift-console.apps.${CLUSTER_DOMAIN}`
2. Click on padlock icon in address bar
3. View certificate details
4. Verify:
   - Issued to: `*.apps.${CLUSTER_DOMAIN}`
   - Issued by: Your CA
   - Valid dates

### 6.3 Test Application Routes

```bash
# Test a few routes
for route in console oauth-openshift; do
  echo "Testing $route..."
  curl -v https://${route}.${APPS_DOMAIN} 2>&1 | grep "SSL certificate verify"
done
```

---

## Troubleshooting

### Issue: Certificate Not Applied

```bash
# Check ingress controller status
oc describe ingresscontroller default -n openshift-ingress-operator | grep -A 10 Status

# Check for errors in operator logs
oc logs -n openshift-ingress-operator deployment/ingress-operator --tail=50

# Verify secret exists and is valid
oc get secret custom-ingress-cert -n openshift-ingress -o yaml
```

### Issue: Certificate Chain Problems

```bash
# Verify certificate chain order
openssl verify -CAfile intermediate.pem ${CERT_PREFIX}.pem

# Check full chain
openssl crl2pkcs7 -nocrl -certfile ${CERT_PREFIX}-fullchain.pem | openssl pkcs7 -print_certs -text -noout | grep Subject:
```

### Issue: Pods Not Restarting

```bash
# Force router pod restart
oc delete pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default

# Scale down and up
oc scale deployment/router-default -n openshift-ingress --replicas=0
oc scale deployment/router-default -n openshift-ingress --replicas=2
```

---

## Rollback Procedure

If issues occur, rollback to default certificate:

```bash
# Remove custom certificate configuration
oc patch ingresscontroller.operator default \
  -n openshift-ingress-operator \
  --type=json \
  --patch='[{"op": "remove", "path": "/spec/defaultCertificate"}]'

# Verify rollback
oc get ingresscontroller.operator default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate}'

# Monitor pod rollout
oc get pods -n openshift-ingress -w

# Optionally delete the secret
oc delete secret custom-ingress-cert -n openshift-ingress
```

---

## Automation Script

Save this as `update-ingress-cert.sh`:

```bash
#!/bin/bash
set -e

# Configuration
ENV_NAME="${1:-dev}"
CERT_PATH="${2:-./certs}"
CLUSTER_DOMAIN="ocp.${ENV_NAME}.example.com"
APPS_DOMAIN="apps.${CLUSTER_DOMAIN}"

echo "=== OpenShift Ingress Certificate Update ==="
echo "Environment: ${ENV_NAME}"
echo "Cluster: ${CLUSTER_DOMAIN}"
echo "Apps Domain: ${APPS_DOMAIN}"
echo ""

# Check files exist
if [[ ! -f "${CERT_PATH}/fullchain.pem" ]] || [[ ! -f "${CERT_PATH}/private.key" ]]; then
    echo "ERROR: Certificate files not found in ${CERT_PATH}"
    echo "Expected: fullchain.pem and private.key"
    exit 1
fi

# Verify certificate
echo "Verifying certificate..."
openssl x509 -in ${CERT_PATH}/fullchain.pem -text -noout | grep "Subject:"

# Login check
echo "Checking OpenShift login..."
oc whoami || { echo "Not logged in to OpenShift"; exit 1; }

# Backup
echo "Creating backup..."
oc get ingresscontroller default -n openshift-ingress-operator -o yaml > backup-ingress-$(date +%Y%m%d-%H%M%S).yaml

# Create/update secret
echo "Creating certificate secret..."
oc delete secret custom-ingress-cert -n openshift-ingress --ignore-not-found
oc create secret tls custom-ingress-cert \
  --cert=${CERT_PATH}/fullchain.pem \
  --key=${CERT_PATH}/private.key \
  -n openshift-ingress

# Update ingress controller
echo "Updating ingress controller..."
oc patch ingresscontroller.operator default \
  -n openshift-ingress-operator \
  --type=merge \
  --patch='{"spec":{"defaultCertificate":{"name":"custom-ingress-cert"}}}'

# Wait for rollout
echo "Waiting for router pods to restart..."
oc rollout status deployment/router-default -n openshift-ingress

echo "=== Certificate update complete ==="
echo "Verify at: https://console-openshift-console.${APPS_DOMAIN}"
```

---

## Certificate Renewal Checklist

- [ ] Generate new CSR with updated validity period
- [ ] Submit certificate request
- [ ] Receive and process certificate bundle
- [ ] Create certificate chain in correct order
- [ ] Verify certificate matches private key
- [ ] Backup current configuration
- [ ] Create secret in openshift-ingress namespace
- [ ] Patch ingress controller
- [ ] Verify pods restart successfully
- [ ] Test certificate in browser
- [ ] Document expiry date for next renewal

---

## Notes

- Certificate renewal should be done during maintenance window
- Keep private key secure - never commit to git
- Test in non-production environment first
- Monitor cluster events during update
- Certificate propagation may take 5-10 minutes
- Some pods may need manual restart to pick up new certificate