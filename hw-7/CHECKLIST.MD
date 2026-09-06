# Чеклист для защиты ДЗ 7

## Подготовка (заранее, не на защите)

```bash
minikube start
minikube addons enable ingress
minikube tunnel          # отдельный терминал, держать открытым
cd hw-7 && ./init.sh     # metrics-server, VPA, приложение, locust-operator
```

Затем **до защиты** прогнать нагрузочную часть и вписать цифры в таблицу
«Результаты исследования» в [README.MD](README.MD):

```bash
SAMPLES=12 INTERVAL=5 ./scripts/04-measure.sh    # покой
./scripts/06-find-max-users.sh                   # максимум пользователей
USERS=<найденный максимум> RUN_TIME=5m ./scripts/07-hpa-demo.sh
```

VPA должен «пожить» под нагрузкой хотя бы 15 минут — иначе в `describe vpa`
не будет рекомендаций.

Три терминала на защите: (1) `minikube tunnel`, (2) команды, (3) наблюдение
(`kubectl get hpa api -n k8s-hw7 -w`).

---

## Порядок демонстрации

### 0. Общая картина

- [ ] Показать что всё запущено:
  ```bash
  kubectl get pods -n k8s-hw7
  kubectl get deployment,statefulset,hpa,vpa -n k8s-hw7
  kubectl get svc,ingress -n k8s-hw7
  ```
- [ ] Объяснить состав: Go API + Postgres (цель нагрузки), metrics-server,
      HPA + VPA, locust-operator.

---

## Часть 1. Метрики и начальные лимиты

### 1.1 metrics-server

- [ ] Показать, что addon включён и метрики идут:
  ```bash
  minikube addons list | grep metrics-server
  kubectl get deployment metrics-server -n kube-system
  kubectl top nodes
  kubectl top pods -n k8s-hw7
  ```
- [ ] Объяснить: «HPA и VPA берут CPU/RAM из `metrics.k8s.io`; без
      metrics-server HPA показывает `<unknown>` и не масштабирует».

### 1.2 Исследование потребления

- [ ] Показать скрипт замера и запустить в покое:
  ```bash
  SAMPLES=6 INTERVAL=5 ./scripts/04-measure.sh
  ```
- [ ] Показать заполненную таблицу «Результаты исследования» в README.MD —
      строку «Покой».

### 1.3 Начальные requests / limits

- [ ] Показать values: `.helm/charts/backend/values.yaml`, блок `resources`.
- [ ] Показать, что они доехали в кластер:
  ```bash
  kubectl get deployment api -n k8s-hw7 \
    -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq
  ```
- [ ] Объяснить логику: `requests` чуть выше покоя, `limits` ~5x — запас на
      всплеск, пока HPA добавляет реплику.

---

## Часть 2. Стресс-тесты на Locust

### 2.1 Locust установлен

- [ ] `locust --version`

### 2.2 Тест на получение ресурсов от API

- [ ] Показать `helm/locust/files/locustfile.py`:
  - `HttpUser`, `wait_time = between(1, 3)`;
  - задачи с весами: `/db/requests` (5), `/db/report` (3), `/db/stats` (2),
    `/healthz` (1) — все GET, «получение ресурсов от API»;
  - объяснить, что это единственная копия файла: из него собирается и
    ConfigMap части 4, и локальные прогоны.
- [ ] Показать, что эндпоинты живые и отвечают из разных подов:
  ```bash
  curl -i http://api-hw7.local/db/requests?limit=3 | grep -i x-pod-name
  curl -s "http://api-hw7.local/db/report?rows=100" | jq
  ```

### 2.3 Настройки Locust

- [ ] Показать `locust/locust.conf`: `host`, `users`, `spawn-rate`,
      `run-time` — ровно те четыре пункта, что просит задание.
- [ ] Запустить короткий прогон:
  ```bash
  USERS=50 SPAWN_RATE=10 RUN_TIME=1m ./scripts/05-locust-local.sh
  ```

### 2.4 Максимум пользователей

- [ ] Показать `scripts/06-find-max-users.sh` и логику остановки:
      ошибки > 0 **или** avg > 5000 ms.
- [ ] Показать таблицу ступеней из прошлого прогона (или запустить
      укороченный вариант):
  ```bash
  STEPS="25 50 100" STEP_RUN_TIME=30s COOLDOWN=10 ./scripts/06-find-max-users.sh
  ```
- [ ] Назвать найденный максимум и показать его в README.MD.

### 2.5 Потребление в критической точке и новые limits

- [ ] Показать строку «Критическая точка» в таблице README.MD.
- [ ] Показать, откуда цифры: `04-measure.sh` параллельно с прогоном.
- [ ] Показать обновлённый блок `resources` и объяснить правило:
      `requests` ≈ критическая точка, `limits` — 1.5–2x поверх максимума.

---

## Часть 3. Настройка масштабирования

### 3.1 HPA создан и настроен

- [ ] Показать манифест `.helm/charts/backend/templates/hpa.yaml` и
      результат:
  ```bash
  kubectl get hpa api -n k8s-hw7
  kubectl describe hpa api -n k8s-hw7
  ```
- [ ] Пройти по best practices (таблица в README.MD):
  - `requests` обязательны — иначе `averageUtilization` не считается;
  - `minReplicas: 2` — одна реплика это точка отказа;
  - цель 70%, а не 90% — запас на время масштабирования;
  - только CPU, без памяти — Go не отдаёт RSS сразу, по памяти HPA не сжался бы;
  - `scaleUp` окно 0 / `scaleDown` окно 300 с — быстро вверх, медленно вниз;
  - `replicas` не рендерится при включённом HPA — иначе upgrade сбрасывал бы масштаб.

### 3.2 HPA под нагрузкой: рост и возврат

- [ ] В терминале наблюдения:
  ```bash
  kubectl get hpa api -n k8s-hw7 -w
  ```
- [ ] Запустить:
  ```bash
  USERS=200 RUN_TIME=5m ./scripts/07-hpa-demo.sh
  ```
- [ ] Показать рост числа подов (2 → 4–6):
  ```bash
  kubectl get pods -n k8s-hw7 -l app.kubernetes.io/name=api
  ```
- [ ] Показать события масштабирования:
  ```bash
  kubectl describe hpa api -n k8s-hw7 | sed -n '/Events:/,$p'
  ```
- [ ] После окна стабилизации (~5 минут после снятия нагрузки) показать
      возврат к 2 репликам — скрипт печатает моменты изменения числа подов
      из своего лога (`locust/results/hpa-demo-*.log`).

### 3.3 VPA установлен и настроен

- [ ] Показать, что контроллеры работают:
  ```bash
  kubectl get pods -n k8s-hw7 -l app.kubernetes.io/instance=vpa
  kubectl get crd | grep autoscaling.k8s.io
  ```
- [ ] Показать манифест `.helm/charts/backend/templates/vpa.yaml`.
- [ ] Пройти по best practices:
  - `updateMode: "Off"` — не конфликтует с HPA по CPU (иначе VPA правит
    знаменатель метрики HPA);
  - `controlledValues: RequestsOnly` — не ломает запас, заложенный в limits;
  - `min/maxAllowed` — рекомендация не уедет в 0m и не превысит узел;
  - `"Off"` в кавычках — иначе YAML прочитает это как boolean.

### 3.4 VPA генерирует рекомендации

- [ ] **Ключевой пункт задания:**
  ```bash
  kubectl describe vpa api -n k8s-hw7
  ```
- [ ] Показать в выводе блок `Recommendation → Container Recommendations`:
      `Target`, `Lower Bound`, `Upper Bound`, `Uncapped Target` — и что там
      есть **memory**.
- [ ] Сравнить рекомендацию VPA с limits, выставленными руками по замерам.

---

## Часть 4. Деплой Locust

### 4.1 locust-operator установлен

- [ ] ```bash
  helm list -n k8s-hw7
  kubectl get pods -n k8s-hw7 -l app.kubernetes.io/name=locust-k8s-operator
  kubectl get crd locusttests.locust.io
  ```

### 4.2 Чарт для деплоя Locust

- [ ] Показать структуру `helm/locust/` и объяснить, почему locustfile лежит
      в чарте (Helm `.Files.Get` не читает за пределами чарта — так остаётся
      один источник правды).
- [ ] **ConfigMap с locustfile.py:**
  ```bash
  kubectl get configmap load-test-v2-locustfile -n k8s-hw7 -o yaml | head -20
  ```
- [ ] **LocustTest с настройками как в части 2:**
  ```bash
  kubectl get locusttest load-test-v2 -n k8s-hw7 -o yaml
  ```
  Показать `master.command`: `--users 100 --spawn-rate 10 --run-time 3m` —
  те же параметры, что в `locust/locust.conf`.
- [ ] Показать Job-ы и поды, созданные оператором:
  ```bash
  kubectl get jobs,pods -n k8s-hw7 | grep load-test-v2
  ```
- [ ] Показать логи прогона:
  ```bash
  kubectl logs -n k8s-hw7 job/load-test-v2-master --tail=30
  ```

### 4.3 Ingress на load-test-v2-webui:8089

- [ ] ```bash
  kubectl get svc load-test-v2-webui -n k8s-hw7
  kubectl get ingress load-test-v2-webui -n k8s-hw7
  ```
- [ ] Открыть web UI: http://locust-hw7.local
- [ ] **Отдельно рассказать про грабли:** оператор создаёт только Service
      `load-test-v2-master` с портами 5557/5558 и намеренно исключает 8089
      (в коде — ветка `if port == WebUIPort { continue }`, документация
      предлагает `kubectl port-forward`). Поэтому Service
      `load-test-v2-webui` объявлен в нашем чарте с селектором
      `performance-test-pod-name: load-test-v2-master`.

---

### 5. Идемпотентность

- [ ] Объяснить: `init.sh` можно запускать повторно (`helm upgrade --install`,
      `kubectl apply`, проверки «уже включено»); `teardown.sh` снимает всё,
      включая CRD VPA, которые Helm сам не удаляет.

---

## Шпаргалка

```bash
# Всё состояние
kubectl get pods,hpa,vpa,locusttest -n k8s-hw7

# Метрики
kubectl top pods -n k8s-hw7 -l app.kubernetes.io/name=api

# Масштабирование
kubectl get hpa api -n k8s-hw7 -w
kubectl describe hpa api -n k8s-hw7 | sed -n '/Events:/,$p'
kubectl describe vpa api -n k8s-hw7

# Нагрузка
USERS=200 RUN_TIME=5m ./scripts/07-hpa-demo.sh
./scripts/06-find-max-users.sh
SAMPLES=40 INTERVAL=5 ./scripts/04-measure.sh

# Locust в кластере
kubectl logs -n k8s-hw7 job/load-test-v2-master -f

# Очистить всё
./teardown.sh
```
