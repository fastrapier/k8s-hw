#!/usr/bin/env bash
set -euo pipefail

# Usage: ./gen-dashboard-token.sh [context]
# Optionally set K8S_CONTEXT or pass as first arg. Default: docker-desktop.
# Set NO_COLOR=1 to disable ANSI colors.
# Generates SHORT-LIVED dashboard token via TokenRequest API (kubectl create token).
# No legacy secret fallback retained (explicitly removed by request).
# Duration configured via TOKEN_DURATION (examples: 3600s, 1h, 30m). Default: 3600s.

DEFAULT_CONTEXT="docker-desktop"
CTX="${1:-${K8S_CONTEXT:-$DEFAULT_CONTEXT}}"
SA_NAME="dashboard-dev"
NAMESPACE="kube-system"
CRB_NAME="${SA_NAME}-admin-binding"
DURATION="${TOKEN_DURATION:-3600s}"

if [[ "${NO_COLOR:-0}" == "1" ]]; then
  RED=""; GREEN=""; YELLOW=""; NC=""; BLUE="";
else
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[1;34m'; NC='\033[0m';
fi

KCTL=(kubectl --context "${CTX}")
info()  { printf '%b\n' "${BLUE}[INFO]${NC} $*" >&2; }
step()  { printf '%b\n' "${YELLOW}[STEP]${NC} $*" >&2; }
ok()    { printf '%b\n' "${GREEN}[OK]${NC} $*" >&2; }
err()   { printf '%b\n' "${RED}[ERR]${NC} $*" >&2; }

info "Using context: ${CTX}"; info "ServiceAccount: ${SA_NAME} namespace: ${NAMESPACE} duration: ${DURATION}";

if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "${CTX}"; then
  err "Kube context '${CTX}' not found."; exit 1
fi

# Ensure SA
if ! "${KCTL[@]}" get sa "${SA_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  step "Creating ServiceAccount ${SA_NAME}"
  "${KCTL[@]}" create sa "${SA_NAME}" -n "${NAMESPACE}" >/dev/null
else
  info "ServiceAccount exists"
fi

# Ensure ClusterRoleBinding
if ! "${KCTL[@]}" get clusterrolebinding "${CRB_NAME}" >/dev/null 2>&1; then
  step "Creating ClusterRoleBinding ${CRB_NAME} -> cluster-admin"
  "${KCTL[@]}" create clusterrolebinding "${CRB_NAME}" \
    --clusterrole=cluster-admin \
    --serviceaccount="${NAMESPACE}:${SA_NAME}" >/dev/null
else
  info "ClusterRoleBinding exists"
fi

step "Requesting ephemeral token (TokenRequest API)"
if ! TOKEN=$("${KCTL[@]}" create token "${SA_NAME}" -n "${NAMESPACE}" --duration="${DURATION}" 2>/dev/null); then
  err "Failed to create ephemeral token. Possible causes: \n  - Kubernetes < 1.24 or kubectl too old\n  - RBAC denies token create\n  - SA / API server issues\nNo legacy fallback (disabled)."; exit 1
fi

if [[ -z "${TOKEN}" ]]; then
  err "Empty token received from API (unexpected)."; exit 1
fi

ok "Ephemeral token generated (valid approx ${DURATION})."
# Decode exp (best effort)
if command -v base64 >/dev/null; then
  PAYLOAD=$(printf '%s' "${TOKEN}" | cut -d'.' -f2 | tr '_-' '/+' | base64 -d 2>/dev/null || true)
  EXP=$(printf '%s' "${PAYLOAD}" | grep -o '"exp"[[:space:]]*:[[:space:]]*[0-9]\+' | head -1 | grep -o '[0-9]\+' || true)
  if [[ -n "${EXP}" ]] && command -v date >/dev/null; then
    WHEN=$(date -r "${EXP}" 2>/dev/null || date -d @"${EXP}" 2>/dev/null || true)
    [[ -n "${WHEN}" ]] && info "Expires (approx): ${WHEN}"
  fi
fi

printf '%s\n' "${TOKEN}"
step "Use the token above in Kubernetes Dashboard (login -> Token)."
