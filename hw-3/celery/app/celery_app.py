from celery import Celery

app = Celery("hw3")
app.config_from_object("app.celeryconfig")
app.autodiscover_tasks(["app"])
