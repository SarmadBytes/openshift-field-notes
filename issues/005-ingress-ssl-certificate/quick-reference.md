# Quick Reference: OpenShift Ingress SSL Certificate Update

## Quick Commands (Copy-Paste Ready)

### 1. Set Environment Variables
```bash
export ENV_NAME="dev"  # Change to: dev, test, preprod, prod
export CLUSTER_DOMAIN="ocp.${ENV_NAME}.example.com"
export APPS_DOMAIN="apps.${CLUSTER_DOMAIN}"
export CERT_PREFIX="ocp-${ENV_NAME}"
```

### 2. Generate CSR
```bash
# Create config
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
OU = OpenShift
CN = *.${APPS_DOMAIN}
emailAddress = openshift@example.com
[req_ext]
subjectAltName = @alt_names
[alt_names]
DNS.1 = *.${APPS_DOMAIN}
EOF

# Generate CSR and key
openssl req -new -out ${CERT_PREFIX}.csr -newkey rsa:2048 -nodes -sha256 -keyout ${CERT_PREFIX}.key -config openssl_san_${CERT_PREFIX}.cnf
```

### 3. After Receiving Certificate
```bash
# Create certificate chain (Server → Intermediate → Root)
cat server.pem intermediate.pem root.pem > fullchain.pem

# Verify certificate matches key
openssl x509 -noout -modulus -in fullchain.pem | openssl md5
openssl rsa -noout -modulus -in ${CERT_PREFIX}.key | openssl md5
```

### 4. Apply to OpenShift
```bash
# Create secret
oc create secret tls custom-ingress-cert \
  --cert=fullchain.pem \
  --key=${CERT_PREFIX}.key \
  -n openshift-ingress

# Update ingress controller
oc patch ingresscontroller.operator default \
  -n openshift-ingress-operator \
  --type=merge \
  --patch='{"spec":{"defaultCertificate":{"name":"custom-ingress-cert"}}}'

# Watch rollout
oc get pods -n openshift-ingress -w
```

### 5. Verify
```bash
# Check certificate
echo | openssl s_client -connect console-openshift-console.${APPS_DOMAIN}:443 2>/dev/null | openssl x509 -noout -subject -dates
```

### 6. Rollback (if needed)
```bash
oc patch ingresscontroller.operator default \
  -n openshift-ingress-operator \
  --type=json \
  --patch='[{"op": "remove", "path": "/spec/defaultCertificate"}]'
```

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| Certificate chain wrong order | Ensure order is: Server → Intermediate → Root |
| Certificate doesn't match key | Regenerate CSR with same key or use correct key |
| Pods not restarting | `oc delete pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default` |
| Certificate not applied | Check operator logs: `oc logs -n openshift-ingress-operator deployment/ingress-operator` |

## Files Structure
```
ocp-dev-certs/
├── openssl_san_ocp-dev.cnf      # OpenSSL config
├── ocp-dev.csr                  # Certificate request
├── ocp-dev.key                  # Private key (KEEP SECURE!)
├── ocp-dev.key.backup           # Backup of private key
├── server.pem                   # Server certificate
├── intermediate.pem             # Intermediate CA cert
├── root.pem                     # Root CA cert (optional)
└── fullchain.pem                # Combined certificate chain
```

## Pre-flight Checklist
- [ ] Cluster domain confirmed
- [ ] OpenSSL installed
- [ ] Logged into correct cluster
- [ ] Maintenance window scheduled
- [ ] Backup commands ready

## Post-Update Checklist
- [ ] All router pods running
- [ ] Certificate shows in browser
- [ ] Console accessible
- [ ] Sample app routes tested
- [ ] Expiry date documented