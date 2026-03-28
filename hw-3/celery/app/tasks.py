import json
import requests
from app.celery_app import app
from app.vault import VaultClient


def _vault():
    return VaultClient()


@app.task(name="fetch_weather")
def fetch_weather(city: str = "Moscow") -> dict:
    vc = _vault()
    api_key = vc.get_secret("secret/weather", "api_key")

    url = f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={api_key}&units=metric"
    resp = requests.get(url)

    if resp.status_code != 200:
        raise RuntimeError(f"Weather API {resp.status_code}: {resp.text}")

    data = resp.json()
    with open("weather_result.json", "w") as f:
        json.dump(data, f, indent=2)

    return {
        "city": city,
        "temp": data.get("main", {}).get("temp"),
        "description": data.get("weather", [{}])[0].get("description"),
    }


@app.task(name="fetch_news")
def fetch_news(query: str = "technology") -> dict:
    vc = _vault()
    api_key = vc.get_secret("secret/news", "api_key")

    url = f"https://newsapi.org/v2/everything?q={query}&apiKey={api_key}&pageSize=5"
    resp = requests.get(url)

    if resp.status_code != 200:
        raise RuntimeError(f"News API {resp.status_code}: {resp.text}")

    data = resp.json()
    with open("news_result.json", "w") as f:
        json.dump(data, f, indent=2)

    articles = [
        {"title": a["title"], "url": a["url"]}
        for a in data.get("articles", [])
    ]
    return {"query": query, "total": data.get("totalResults", 0), "articles": articles}
