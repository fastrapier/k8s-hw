#!/usr/bin/env bash
set -euo pipefail

# Usage: ./gen-dashboard-token.sh [context]
# Optionally set K8S_CONTEXT or pass as first arg. Default: docker-desktop.
# Set NO_COLOR=1 to disable ANSI colors.
# Creates (if absent) ServiceAccount + ClusterRoleBinding + token Secret and prints token.

DEFAULT_CONTEXT="docker-desktop"
CTX="${1:-${K8S_CONTEXT:-$DEFAULT_CONTEXT}}"
SA_NAME="dashboard-dev"
NAMESPACE="kube-system"
SECRET_NAME="${SA_NAME}-token"
CRB_NAME="${SA_NAME}-admin-binding"

# Colors (disable with NO_COLOR=1)
if [[ "${NO_COLOR:-0}" == "1" ]]; then
  RED=""; GREEN=""; YELLOW=""; NC=""; BLUE="";
else
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[1;34m'; NC='\033[0m';
fi

KCTL=(kubectl --context "${CTX}")

info()  { printf '%b\n' "${BLUE}[INFO]${NC} $*" >&2; }
step()  { printf '%b\n' "${YELLOW}[STEP]${NC} $*" >&2; }
ok()    { printf '%b\n' "${GREEN}[OK]${NC} $*" >&2; }
warn()  { printf '%b\n' "${RED}[WARN]${NC} $*" >&2; }
error() { printf '%b\n' "${RED}[ERROR]${NC} $*" >&2; }

info "Using context: ${CTX}"

# Soft context presence check
if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "${CTX}"; then
  warn "Context '${CTX}' not found in kubeconfig (continuing, kubectl may fail)."
fi

# Ensure ServiceAccount
if ! "${KCTL[@]}" get sa "${SA_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  step "Creating ServiceAccount ${SA_NAME} in ${NAMESPACE}"
  "${KCTL[@]}" create sa "${SA_NAME}" -n "${NAMESPACE}" >/dev/null
else
  info "ServiceAccount ${SA_NAME} already exists"
fi

# Ensure ClusterRoleBinding
if ! "${KCTL[@]}" get clusterrolebinding "${CRB_NAME}" >/dev/null 2>&1; then
  step "Creating ClusterRoleBinding ${CRB_NAME} (cluster-admin)"
  "${KCTL[@]}" create clusterrolebinding "${CRB_NAME}" \
    --clusterrole=cluster-admin \
    --serviceaccount="${NAMESPACE}:${SA_NAME}" >/dev/null
else
  info "ClusterRoleBinding ${CRB_NAME} already exists"
fi

# Ensure Secret
if ! "${KCTL[@]}" get secret "${SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  step "Creating token Secret ${SECRET_NAME}"
  cat <<EOF | "${KCTL[@]}" apply -f - >/dev/null
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
  info "Secret ${SECRET_NAME} already exists"
fi

step "Waiting for token data..."
for i in {1..30}; do
  TOK=$("${KCTL[@]}" get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.token}' 2>/dev/null || true)
  if [[ -n "${TOK}" ]]; then
    if command -v base64 >/dev/null; then
      TOKEN_DECODED=$(printf '%s' "${TOK}" | base64 -d 2>/dev/null || printf '%s' "${TOK}" | base64 -D 2>/dev/null || true)
    else
      error "base64 utility not found"; exit 1
    fi
    if [[ -z "${TOKEN_DECODED}" ]]; then
      error "Failed to decode token"
      exit 1
    fi
    ok "Token ready (copy below)."
    printf '%s\n' "${TOKEN_DECODED}"
    step "Tip: Use this value in Dashboard login (Token)."
    exit 0
  fi
  sleep 0.5
  if [[ $i -eq 30 ]]; then
    error "Timed out waiting for token in secret ${SECRET_NAME}"
    exit 1
  fi
done
