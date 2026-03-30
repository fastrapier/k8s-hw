#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_vals

echo "=== Vault login ==="
vault_login

echo "=== Получение пароля Redis из Vault ==="
REDIS_PASSWORD=$(kubectl exec "$VAULT_POD" -n "$NAMESPACE" -- vault kv get -field=password secret/redis)

echo "=== Деплой Redis (redis-stack-server) ==="
helm_cleanup_pending redis

# Свой чарт на базе redis-stack-server: StatefulSet + Headless Service + LoadBalancer
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Service
metadata:
  name: redis-headless
  namespace: $NAMESPACE
spec:
  clusterIP: None
  selector:
    app: redis
  ports:
    - port: 6379
      targetPort: 6379
      name: redis
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: $NAMESPACE
spec:
  type: LoadBalancer
  selector:
    app: redis
  ports:
    - port: 6379
      targetPort: 6379
      name: redis
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: $NAMESPACE
spec:
  serviceName: redis-headless
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis/redis-stack-server:latest
          ports:
            - containerPort: 6379
          env:
            - name: REDIS_ARGS
              value: "--requirepass $REDIS_PASSWORD"
          volumeMounts:
            - name: redis-data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: redis-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
EOF

echo "[INFO] Ожидание готовности Redis..."
kubectl rollout status statefulset/redis -n "$NAMESPACE" --timeout=300s

echo "=== Деплой RedisInsight ==="
add_helm_repo heywood8 https://heywood8.github.io/helm-charts
helm_cleanup_pending redisinsight

helm upgrade --install redisinsight heywood8/redisinsight \
  --namespace "$NAMESPACE" \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set "ingress.hosts[0].host=$REDIS_HOST" \
  --set "ingress.hosts[0].paths[0]=/" \
  --set persistence.enabled=true \
  --set persistence.size=1Gi \
  --wait --timeout=5m

add_host "$REDIS_HOST"

echo ""
echo "[OK] Redis и RedisInsight задеплоены"
echo "[INFO] RedisInsight UI: http://$REDIS_HOST (нужен minikube tunnel)"
echo "[INFO] Redis: redis.$NAMESPACE.svc.cluster.local:6379"
