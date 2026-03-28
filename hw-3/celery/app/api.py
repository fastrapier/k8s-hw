from fastapi import FastAPI
from celery.result import AsyncResult
from app.celery_app import app as celery_app
from app.tasks import fetch_weather, fetch_news

api = FastAPI(title="HW3 Celery API", version="1.0.0")


@api.post("/tasks/weather")
def run_weather(city: str = "Moscow"):
    task = fetch_weather.delay(city)
    return {"task_id": task.id, "status": "PENDING"}


@api.post("/tasks/news")
def run_news(q: str = "technology"):
    task = fetch_news.delay(q)
    return {"task_id": task.id, "status": "PENDING"}


@api.get("/tasks/{task_id}")
def get_task_status(task_id: str):
    result = AsyncResult(task_id, app=celery_app)
    response = {"task_id": task_id, "status": result.status}
    if result.ready():
        if result.successful():
            response["result"] = result.result
        else:
            response["error"] = str(result.result)
    return response


@api.get("/health")
def health():
    return {"status": "ok"}
