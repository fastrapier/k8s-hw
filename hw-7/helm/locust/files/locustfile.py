"""Нагрузочный тест HW7: получение ресурсов от API.

Единственный источник правды для locustfile: этот файл монтируется в поды
locust-operator через ConfigMap (Helm .Files.Get не умеет читать за пределы
каталога чарта, поэтому файл лежит здесь), и на него же ссылаются локальные
скрипты hw-7/scripts/05-locust-local.sh и 06-find-max-users.sh.
"""

import os

from locust import HttpUser, between, task


class ApiUser(HttpUser):
    # Пауза между запросами одного пользователя: без неё «100 пользователей»
    # означали бы 100 бесконечных циклов, а не 100 реальных клиентов.
    wait_time = between(1, 3)

    def on_start(self):
        host_header = os.getenv("LOCUST_HOST_HEADER")
        if host_header:
            self.client.headers["Host"] = host_header

    @task(5)
    def list_requests(self):
        """Постраничное чтение таблицы requests — самый частый запрос."""
        self.client.get("/db/requests?limit=25", name="GET /db/requests")

    @task(3)
    def report(self):
        """Тяжёлый запрос: SELECT + хеширование, основной источник CPU-нагрузки."""
        self.client.get("/db/report?rows=100", name="GET /db/report")

    @task(2)
    def stats(self):
        """Агрегаты по таблице."""
        self.client.get("/db/stats", name="GET /db/stats")

    @task(1)
    def healthz(self):
        """Дешёвый запрос — фон, по нему видно деградацию времени ответа."""
        self.client.get("/healthz", name="GET /healthz")
