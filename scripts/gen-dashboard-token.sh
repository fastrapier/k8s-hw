#!/usr/bin/env bash
set -euo pipefail

REQUIRED_CTX="docker-desktop"
SA_NAME="dashboard-dev"
NAMESPACE="kube-system"
SECRET_NAME="${SA_NAME}-token"

# Colors (optional)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ctx="$(kubectl config current-context 2>/dev/null || echo '')"
if [[ "$ctx" != "$REQUIRED_CTX" ]]; then
  echo -e "${RED}[ERROR] Current context '$ctx' != required '$REQUIRED_CTX'.${NC}" >&2
  echo "Switch first: kubectl config use-context $REQUIRED_CTX" >&2
  exit 1
fi

echo -e "${GREEN}[INFO] Using context: $ctx${NC}" >&2

# Ensure ServiceAccount
if ! kubectl get sa "$SA_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo -e "${YELLOW}[STEP] Creating ServiceAccount $SA_NAME in $NAMESPACE${NC}" >&2
  kubectl create sa "$SA_NAME" -n "$NAMESPACE" >/dev/null
else
  echo -e "${GREEN}[INFO] ServiceAccount $SA_NAME already exists${NC}" >&2
fi

# Ensure ClusterRoleBinding (cluster-admin for convenience; narrow in real env)
CRB_NAME="${SA_NAME}-admin-binding"
if ! kubectl get clusterrolebinding "$CRB_NAME" >/dev/null 2>&1; then
  echo -e "${YELLOW}[STEP] Creating ClusterRoleBinding $CRB_NAME (cluster-admin)${NC}" >&2
  kubectl create clusterrolebinding "$CRB_NAME" --clusterrole=cluster-admin --serviceaccount="${NAMESPACE}:${SA_NAME}" >/dev/null
else
  echo -e "${GREEN}[INFO] ClusterRoleBinding $CRB_NAME already exists${NC}" >&2
fi

# Create / ensure token Secret
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo -e "${YELLOW}[STEP] Creating token Secret $SECRET_NAME${NC}" >&2
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF
else
  echo -e "${GREEN}[INFO] Secret $SECRET_NAME already exists${NC}" >&2
fi

# Wait for token population
echo -e "${YELLOW}[STEP] Waiting for token data...${NC}" >&2
for i in {1..30}; do
  TOK=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null || true)
  if [[ -n "${TOK}" ]]; then
    TOKEN_DECODED=$(echo -n "$TOK" | base64 -d)
    echo -e "${GREEN}[OK] Token ready (copy below).${NC}" >&2
    echo "$TOKEN_DECODED"
    echo -e "${YELLOW}Tip:${NC} Use this in Dashboard login (Token)." >&2
    exit 0
  fi
  sleep 0.5
  if [[ $i -eq 30 ]]; then
    echo -e "${RED}[ERROR] Timed out waiting for token in secret $SECRET_NAME${NC}" >&2
    exit 1
  fi
done

