import os

broker_url = os.getenv("CELERY_BROKER_URL", "amqp://guest:guest@localhost:5672/")
result_backend = "rpc://"

task_serializer = "json"
result_serializer = "json"
accept_content = ["json"]
timezone = "UTC"
