import os

broker_url = os.getenv("CELERY_BROKER_URL", "amqp://guest:guest@localhost:5672/")
result_backend = os.getenv("CELERY_RESULT_BACKEND", "redis://localhost:6379/0")

task_serializer = "json"
result_serializer = "json"
accept_content = ["json"]
timezone = "UTC"
