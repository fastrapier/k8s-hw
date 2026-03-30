# Чеклист для защиты ДЗ 4

## Подготовка

```bash
minikube start
minikube tunnel        # отдельный терминал
cd hw-4 && ./init.sh   # ~7 минут
```

---

## Порядок демонстрации

### 1. Инфраструктура

- [ ] Показать что всё запущено:
  ```bash
  kubectl get pods -n k8s-hw4
  kubectl get cronjob -n k8s-hw4
  kubectl get svc -n k8s-hw4
  kubectl get ingress -n k8s-hw4
  ```

### 2. Vault — секрет Redis

- [ ] Показать секреты в Vault (включая новый `secret/redis`):
  ```bash
  kubectl exec vault-0 -n k8s-hw4 -- vault kv get secret/redis
  kubectl exec vault-0 -n k8s-hw4 -- vault kv get secret/rabbitmq
  ```
- [ ] Объяснить: «Пароль Redis хранится в Vault, приложение получает его через AppRole»

### 3. Redis (Часть 1)

- [ ] Показать Redis StatefulSet + Headless Service + LoadBalancer:
  ```bash
  kubectl get statefulset redis -n k8s-hw4
  kubectl get svc redis redis-headless -n k8s-hw4
  ```
- [ ] Показать что Redis работает:
  ```bash
  kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass PING
  ```
- [ ] Объяснить: «Используется redis-stack-server (Redis + модули), StatefulSet для persistence, пароль из Vault»

### 4. RedisInsight

- [ ] Открыть RedisInsight: http://redisinsight-hw4.local
- [ ] Добавить подключение к Redis:
  - Host: `redis.k8s-hw4.svc.cluster.local`
  - Port: `6379`
  - Password: `redis_secret_pass`
- [ ] Показать ключи кэша в интерфейсе

### 5. CacheManager (Часть 2)

- [ ] Показать код: `internal/cache/manager.go`
- [ ] Ключевые моменты:
  - Получает `REDIS_HOST` и `REDIS_PASSWORD` из env
  - Методы: `Get(key)`, `Set(key, value, ttl)`, `Exists(key)`
  - Работает с TTL

### 6. Кэширование API-запросов

- [ ] Показать логи — первый вызов `[API CALL]`, второй `[CACHE HIT]`:
  ```bash
  kubectl logs deployment/consumer-weather -n k8s-hw4 --tail=15
  kubectl logs deployment/consumer-news -n k8s-hw4 --tail=15
  ```

- [ ] Показать ключи в Redis:
  ```bash
  kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass KEYS '*'
  ```

- [ ] Показать TTL ключа:
  ```bash
  kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass TTL weather:Moscow
  ```

- [ ] Очистить кэш и показать что следующий вызов пойдёт в API:
  ```bash
  kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass FLUSHDB
  ```
  Подождать минуту, проверить логи — должен быть `[API CALL]`:
  ```bash
  kubectl logs deployment/consumer-weather -n k8s-hw4 --tail=5
  ```

- [ ] Показать код: `internal/tasks/weather.go`, `internal/tasks/news.go`
- [ ] Объяснить логику:
  1. Проверяем Redis (`cm.Get`)
  2. Есть? → `[CACHE HIT]`, возвращаем из кэша
  3. Нет? → `[API CALL]`, вызываем API → `[CACHE SET]` с TTL → возвращаем результат

### 7. Helm-чарт — Redis в подах

- [ ] Показать ConfigMap с Redis host:
  ```bash
  kubectl get configmap app-config -n k8s-hw4 -o yaml
  ```
- [ ] Показать что `REDIS_HOST` передаётся в поды через `envFrom`

### 8. Идемпотентность

- [ ] Объяснить: «`init.sh` идемпотентный, `teardown.sh` полная очистка»

---

## Шпаргалка

```bash
# Поды
kubectl get pods -n k8s-hw4

# Логи (видно CACHE HIT / API CALL)
kubectl logs -f deployment/consumer-weather -n k8s-hw4
kubectl logs -f deployment/consumer-news -n k8s-hw4

# Redis ключи и TTL
kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass KEYS '*'
kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass TTL weather:Moscow

# Очистить кэш
kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass FLUSHDB

# Очистить всё
./teardown.sh
```
