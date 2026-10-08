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

# /metrics может отдавать метрики процесса при выключенном сборе метрик NGINX.
# Для счётчика запросов нужен явный --enable-metrics=true.
ARGS="$(kubectl get deployment ingress-nginx-controller -n "$INGRESS_NAMESPACE" \
  -o json | jq -c '.spec.template.spec.containers[0].args')"
if jq -e 'any(.[]; . == "--enable-metrics=true" or . == "--enable-metrics")' \
  <<< "$ARGS" >/dev/null; then
  echo "[OK] Метрики ingress-nginx включены (порт 10254)"
else
  echo "[INFO] Включаю сбор метрик NGINX (--enable-metrics=true)"
  PATCH="$(jq -c '[{op: "replace", path: "/spec/template/spec/containers/0/args", value: (map(select(. != "--enable-metrics" and (startswith("--enable-metrics=") | not))) + ["--enable-metrics=true"])}]' <<< "$ARGS")"
  kubectl patch deployment ingress-nginx-controller -n "$INGRESS_NAMESPACE" --type=json \
    -p="$PATCH"
  kubectl rollout status deployment/ingress-nginx-controller -n "$INGRESS_NAMESPACE" --timeout=300s
fi

echo ""
echo "[OK] helmfile готов, addon ingress включён"
