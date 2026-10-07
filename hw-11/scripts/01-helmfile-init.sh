#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "=== Установка helmfile ==="
if command -v helmfile &>/dev/null; then
  echo "[INFO] helmfile уже установлен: $(helmfile version --output short 2>/dev/null || helmfile version 2>&1 | head -1)"
else
  require_cmd brew "https://brew.sh"
  brew install helmfile
  echo "[OK] helmfile установлен"
fi

echo "=== Инициализация helmfile ==="
# helmfile init проверяет helm и доставляет плагины (helm-diff нужен для apply/diff).
helmfile init --force

echo "=== Плагины helm ==="
helm plugin list

ensure_minikube

echo "=== Addon ingress ==="
if minikube -p "$MINIKUBE_PROFILE" addons list -o json 2>/dev/null | grep -A2 '"ingress"' | grep -q '"Status": *"enabled"'; then
  echo "[INFO] addon ingress уже включён"
else
  minikube -p "$MINIKUBE_PROFILE" addons enable ingress
fi

echo "[INFO] Ожидание готовности ingress-nginx..."
kubectl rollout status deployment/ingress-nginx-controller \
  -n "$INGRESS_NAMESPACE" --timeout=300s

# Контроллер отдаёт /metrics на 10254, потому что --enable-metrics по умолчанию true
# и манифест addon-а его не выключает. Если когда-нибудь выключат — метрик не будет,
# поэтому проверяем явно.
if kubectl get deployment ingress-nginx-controller -n "$INGRESS_NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | grep -q 'enable-metrics=false'; then
  echo "[WARN] У контроллера ingress-nginx метрики выключены (--enable-metrics=false)."
  echo "       Включаю метрики на :10254"
  PATCH="$(kubectl get deployment ingress-nginx-controller -n "$INGRESS_NAMESPACE" -o json \
    | jq -c '[{op: "replace", path: "/spec/template/spec/containers/0/args", value: (.spec.template.spec.containers[0].args | map(if . == "--enable-metrics=false" then "--enable-metrics=true" else . end))}]')"
  kubectl patch deployment ingress-nginx-controller -n "$INGRESS_NAMESPACE" --type=json \
    -p="$PATCH"
  kubectl rollout status deployment/ingress-nginx-controller -n "$INGRESS_NAMESPACE" --timeout=300s
else
  echo "[OK] Метрики ingress-nginx включены (порт 10254)"
fi

echo ""
echo "[OK] helmfile готов, addon ingress включён"
