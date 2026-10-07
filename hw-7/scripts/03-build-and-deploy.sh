#!/bin/bash
# ЧАСТИ 1 и 3 — сборка образов и деплой: API с requests/limits, Postgres, HPA, VPA.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_werf
ensure_ghcr_login
ensure_namespace

echo "=== ghcr.io imagePullSecret ==="
create_ghcr_pull_secret

echo "=== /etc/hosts ==="
add_host "$API_HOST"

echo "=== werf converge ==="
cd "$PROJECT_ROOT"
WERF_HELM_PLUGINS=$(mktemp -d)
trap 'rmdir "$WERF_HELM_PLUGINS" 2>/dev/null || true' EXIT
DOCKER_BUILDKIT=1 HELM_PLUGINS="$WERF_HELM_PLUGINS" werf converge --dev \
  --repo "$GHCR_REPO" \
  --namespace "$NAMESPACE"

check_db_schema

echo ""
echo "=== Состояние ==="
kubectl get deployment,statefulset,hpa,vpa -n "$NAMESPACE" 2>/dev/null || true
kubectl get pods -n "$NAMESPACE" -l "$API_SELECTOR"

echo ""
echo "=== requests / limits API ==="
kubectl get deployment "$API_DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\t"}{.resources}{"\n"}{end}'

echo ""
echo "[OK] Приложение задеплоено"
echo "  API:        http://$API_HOST/healthz  (нужен minikube tunnel)"
echo "  Swagger:    http://$API_HOST/swagger"
echo "  Замер:      ./scripts/04-measure.sh"
