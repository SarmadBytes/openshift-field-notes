#!/bin/bash
# Example per-cluster settings for the ingress certificate renewal runbook.
# Copy this file once per cluster (e.g. dmz-preprod-config.sh, dc1-internal-preprod-config.sh,
# dmz-dr-config.sh — the names used in renewal-runbook.md) and fill in your own values.

# Environment
export CLUSTER_NAME="ocp-dmz"
export CLUSTER_DOMAIN="ocp-dmz.example.internal"
export APPS_DOMAIN="apps.${CLUSTER_DOMAIN}"
export API_DOMAIN="api.${CLUSTER_DOMAIN}"
export ENV_NAME="dmz-preprod"
export ENV_TYPE="preprod"

# Certificate details
export CERT_PREFIX="${CLUSTER_NAME}-${ENV_TYPE}-$(date +%Y%m%d)"
export DAYS_VALIDITY=365

# Working directory
export WORK_DIR="${HOME}/ssl-renewal/${ENV_NAME}"
mkdir -p "${WORK_DIR}"

# OpenSSL request config (wildcard for the apps domain)
cat > "${WORK_DIR}/openssl_${ENV_NAME}.cnf" <<EOF
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no
default_md = sha256

[ req_distinguished_name ]
C = XX
ST = Region
L = City
O = Example Org
OU = OpenShift Platform
CN = *.${APPS_DOMAIN}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = *.${APPS_DOMAIN}
DNS.2 = ${APPS_DOMAIN}
EOF

echo "Config loaded for ${CLUSTER_NAME} (${ENV_NAME}); work dir: ${WORK_DIR}"
