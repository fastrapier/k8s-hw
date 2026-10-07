# Чеклист для защиты ДЗ 10

## Подготовка

Команды ниже выполняются из `hw-10/`. Кластер и ARC-раннер из ДЗ 8
уже должны работать. Каждый шаг запускайте отдельно и проверяйте его вывод.

```bash
cd /Users/notwork/dopki/k8s-hw/hw-10
export MINIKUBE_PROFILE=k8s-exam
./scripts/01-precommit.sh
./scripts/06-trufflehog-local.sh
./scripts/05-trivy-local.sh
./scripts/02-deploy-sonarqube.sh  # первый старт может занять до 15 минут
./scripts/03-configure-sonarqube.sh --set-secrets
```

Основной показ анализа — джоба SonarQube в GitHub Actions и отчёт в UI.
`./scripts/04-sonar-scan-local.sh` — необязательный запуск для диагностики.

Для UI можно обойтись без туннеля и DNS `.local`: в отдельном терминале
держите `kubectl --context=k8s-exam port-forward -n k8s-hw10 svc/sonarqube-sonarqube 9000:9000`
и откройте http://127.0.0.1:9000. Логин `admin`, пароль из Keychain
(команда приведена ниже). Скрипты настройки и сканирования также используют порт 9000.

`--set-secrets` сохраняет токен и внутрикластерный URL в GitHub Actions.
Workflow до мержа запускается через событие `pull_request` после push ветки;
`workflow_dispatch` станет доступен, когда workflow попадёт в `main`.

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
  - таблицу уязвимостей с установленными и исправленными версиями;
  - таблицу misconfig, например правила
    (`KSV-0118` дефолтный security context, `KSV-0014` root-fs не read-only,
    `DS-0002` образ работает root-ом);
  - блок **Suppressed Vulnerabilities** — исключения для ДЗ 1-2 с текстом
    обоснования прямо в таблице. Числа и severity меняются с базой Trivy.

- [ ] Объяснить результат подготовки 7 октября: гейт выявил 10 CRITICAL
  в ДЗ 3, 4, 7 и 9. Обновление `amqp091-go` до 1.13.0 и `pgx/v5` до 5.9.0
  позволило пройти повторный гейт без новых исключений. Подробности — в README.

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
- [ ] Показать джобу `sonarqube`: анализ выполнен на `hw8-minikube`, отчёт
  появился в UI. При отсутствии секретов анализ пропускается с warning.
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
  метка `HW8_RUNNER`. Fallback действует только при пустой переменной;
  с заданной меткой и выключенным кластером джоба ждёт раннер».
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
  ./scripts/03-configure-sonarqube.sh --set-secrets
  ```
- [ ] После повторной настройки обновить секреты CI: скрипт пересоздаёт токен,
  а без `--set-secrets` в GitHub останется отозванное значение.
- [ ] Объяснить: «Пароль и passcode берутся из Keychain, а не генерируются
  заново — иначе повторный запуск ломал бы уже выданный CI-токен. Проект
  создаётся с проверкой `key already exists`. Токен отзывается и выдаётся
  заново, потому что SonarQube показывает его ровно один раз».

---

## Шпаргалка

```bash
# Локальные прогоны
brew install sonar-scanner  # CLI для Mac, без эмуляции Docker-образа amd64
./scripts/04-sonar-scan-local.sh
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
