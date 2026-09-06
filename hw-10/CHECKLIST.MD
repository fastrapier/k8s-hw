# Чеклист для защиты ДЗ 10

## Подготовка

```bash
minikube start
minikube tunnel        # отдельный терминал
cd hw-10 && ./init.sh  # ~10-15 минут, первый старт SonarQube долгий
```

Если кластер поднимать не нужно — достаточно `./scripts/01-precommit.sh`,
части 1 и 2 демонстрируются без Kubernetes.

---

## Порядок демонстрации

### 1. Что и где лежит

- [ ] Показать, что часть файлов обязана быть в корне, и объяснить почему:
  ```bash
  ls -1 .pre-commit-config.yaml sonar-project.properties .trivyignore.yaml
  ls -1 .github/workflows/hw10-security.yml
  ```
- [ ] Объяснить: «GitHub читает workflow только из `.github/workflows/`,
  pre-commit ищет конфиг в корне репозитория, sonar-scanner и Trivy
  сканируют репозиторий целиком»

### 2. TruffleHog — pre-commit ловит секрет

- [ ] Показать, что хуки установлены:
  ```bash
  pre-commit run --all-files
  ```
  Все хуки зелёные.

- [ ] **Демонстрация срабатывания.** Кладём фейковый AWS-ключ и просим
  TruffleHog его найти:
  ```bash
  mkdir -p /tmp/th-demo
  printf 'aws_access_key_id = AKIAY4ICPFP0H4SS9UFR\naws_secret_access_key = nXE79SjJ6w+o+kM1iBsxB8caDtOEhaP7NIzF4zCL\n' \
    > /tmp/th-demo/creds.ini

  # Ключ найден: Detector Type: AWS
  trufflehog filesystem /tmp/th-demo --results=verified,unknown,unverified --no-update
  ```
  Ожидаемо: `Detector Type: AWS`, `unverified_secrets: 1`, код возврата
  ненулевой при `--fail`.

- [ ] **Объяснить главный нюанс**, почему нужен `unverified`:
  ```bash
  # Тот же файл в режиме пайплайна — находок НЕТ
  trufflehog filesystem /tmp/th-demo --results=verified,unknown --no-update
  ```
  «`verified` — секрет подтверждён обращением к провайдеру, `unknown` —
  проверить не удалось. Наш ключ выдуман, AWS явно отвечает «невалиден»,
  поэтому он `unverified` и в пайплайн не попадает. Это и защищает CI от
  ложных срабатываний на dev-заглушках прошлых ДЗ.»

- [ ] Показать, что в репозитории действительно чисто — даже в самом
  широком режиме:
  ```bash
  ./scripts/06-trufflehog-local.sh --all
  ```
  Ожидаемо: `0` находок и в истории, и в рабочем дереве.

- [ ] Показать `detect-private-key` на приватном ключе:
  ```bash
  ssh-keygen -t rsa -b 2048 -N '' -C demo -f /tmp/th-demo/id_rsa -q
  cp /tmp/th-demo/id_rsa ./leaked_key
  pre-commit run detect-private-key --files leaked_key   # Failed
  rm -f ./leaked_key
  ```

- [ ] Убрать за собой: `rm -rf /tmp/th-demo`

### 3. Trivy — уязвимости и misconfig

- [ ] Прогнать локально:
  ```bash
  ./scripts/05-trivy-local.sh
  ```

- [ ] Показать в выводе три вещи:
  - таблицу уязвимостей: 18 находок HIGH+CRITICAL, у всех есть фикс;
  - таблицу misconfig: 46 HIGH, всего три правила
    (`KSV-0118` дефолтный security context, `KSV-0014` root-fs не read-only,
    `DS-0002` образ работает root-ом);
  - блок **Suppressed Vulnerabilities** — три CRITICAL с текстом обоснования
    прямо в таблице.

- [ ] Показать реестр принятых рисков:
  ```bash
  cat ../.trivyignore.yaml
  ```
- [ ] Объяснить: «У каждой записи обязателен `statement` — почему риск принят,
  и `expired_at` — когда исключение перестанет действовать. Бессрочных нет.
  Три CRITICAL — в `hw1-2`, это сданное ДЗ; подъём драйвера БД тянет
  перепроверку миграций и относится к ДЗ 1-2».

- [ ] Объяснить, почему misconfig не валит пайплайн: «46 находок в учебных
  чартах — это упрощения стенда. Если бы они валили сборку, пайплайн был бы
  красным всегда, а красный всегда — то же самое, что выключенный».

- [ ] Показать гейт: только CRITICAL, только с доступным фиксом
  (`ignore-unfixed`) — то, на что можно реально отреагировать.

### 4. Пайплайн в GitHub Actions

- [ ] Открыть прогон:
  ```bash
  gh run list --workflow hw10-security.yml
  gh run view --web
  ```
- [ ] Показать зелёные джобы `trufflehog` и `trivy`.
- [ ] Показать джобу `sonarqube`: пропущена с `::warning::`, потому что
  секреты `SONAR_TOKEN` / `SONAR_HOST_URL` не заданы.
- [ ] Показать Job summary: режим сканирования TruffleHog, раннер SonarQube.
- [ ] Показать четыре триггера в workflow и объяснить `schedule`: «базы
  уязвимостей обновляются без нас, код может быть неизменным, а находки
  появиться».
- [ ] Объяснить отсутствие фильтра `paths` (в отличие от ДЗ 8): «секрет или
  уязвимая зависимость могут приехать в любой директории».
- [ ] Если Code scanning доступен — показать вкладку Security с алертами Trivy.

### 5. SonarQube в Kubernetes

- [ ] Показать, что поднято:
  ```bash
  kubectl get pods,svc,ingress,pvc -n k8s-hw10
  ```
- [ ] Показать, что это Community Build:
  ```bash
  kubectl get statefulset sonarqube-sonarqube -n k8s-hw10 \
    -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
  ```
  Ожидаемо: `sonarqube:<версия>-community`.

- [ ] Открыть UI: http://sonarqube-hw10.local
  Логин `admin`, пароль:
  ```bash
  security find-generic-password -a fastrapier -s sonarqube-hw10 -w
  ```
- [ ] Объяснить: «Пароль генерируется скриптом и лежит в Keychain, в
  репозиторий не попадает. `monitoringPasscode` тоже — чарт без него вообще
  не собирается».

- [ ] Показать проект `k8s-hw` и результаты анализа:
  http://sonarqube-hw10.local/dashboard?id=k8s-hw
  — баги, code smells, покрытие Go (в `hw1-2/internal/handler` есть тесты).

- [ ] Прогнать анализ на глазах:
  ```bash
  ./scripts/04-sonar-scan-local.sh
  ```

### 6. Почему SonarQube требует self-hosted раннер

- [ ] Показать строку в workflow:
  ```bash
  grep -n 'HW8_RUNNER' ../.github/workflows/hw10-security.yml
  ```
- [ ] Объяснить: «SonarQube живёт в minikube, у GitHub-hosted раннера до него
  нет сети — та же проблема, что у джобы `deploy` в ДЗ 8, и то же решение:
  метка `HW8_RUNNER` с обязательным fallback. Без fallback джоба висела бы
  в очереди до таймаута, когда minikube выключен».
- [ ] Показать два варианта `SONAR_HOST_URL`:
  - раннер в кластере: `http://sonarqube-sonarqube.k8s-hw10.svc:9000`
  - раннер снаружи: внешний адрес SonarQube
- [ ] Показать, что скрипт печатает команды, но сам секреты не ставит:
  ```bash
  ./scripts/03-configure-sonarqube.sh          # печатает gh secret set ...
  ./scripts/03-configure-sonarqube.sh --set-secrets   # выставляет
  ```

### 7. Идемпотентность

- [ ] Запустить повторно — ничего не сломается:
  ```bash
  ./init.sh
  ```
- [ ] Объяснить: «Пароль и passcode берутся из Keychain, а не генерируются
  заново — иначе повторный запуск ломал бы уже выданный CI-токен. Проект
  создаётся с проверкой `key already exists`. Токен отзывается и выдаётся
  заново, потому что SonarQube показывает его ровно один раз».

---

## Шпаргалка

```bash
# Локальные прогоны
./scripts/05-trivy-local.sh
./scripts/06-trufflehog-local.sh --all
pre-commit run --all-files

# Пайплайн
gh workflow run hw10-security.yml
gh run list --workflow hw10-security.yml

# SonarQube
kubectl get pods -n k8s-hw10
security find-generic-password -a fastrapier -s sonarqube-hw10 -w
open http://sonarqube-hw10.local/dashboard?id=k8s-hw

# Очистить всё
./teardown.sh
kubectl delete namespace k8s-hw10
```
