FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ app/

CMD ["celery", "-A", "app.celery_app", "worker", "--loglevel=info"]
