#!/usr/bin/env python3
"""Форматирование JSON-ответов Prometheus / Loki / Grafana для вывода в терминал.

Читает JSON со stdin, режим — первым аргументом. Вынесено в отдельный файл,
чтобы не экранировать python внутри bash-скриптов.
"""
import json
import sys

INTERESTING_LABELS = ("ingress", "status", "method", "host", "namespace", "pod", "job", "le")


def _load():
    try:
        return json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"  не удалось разобрать ответ как JSON: {exc}")
        sys.exit(1)


def prom_targets():
    data = _load().get("data", {}).get("activeTargets", [])
    found = [
        t for t in data
        if "ingress" in (t.get("labels", {}).get("job") or "")
        or t.get("labels", {}).get("service") == "ingress-metrics"
    ]
    if not found:
        print("  таргет ingress-metrics не найден среди активных")
        print(f"  всего активных таргетов: {len(data)}")
        sys.exit(1)
    for t in found:
        labels = t.get("labels", {})
        print(f"  job={labels.get('job')} health={t.get('health')} url={t.get('scrapeUrl')}")
        if t.get("lastError"):
            print(f"    lastError: {t['lastError']}")
    if not any(t.get("health") == "up" for t in found):
        sys.exit(1)


def prom_query():
    r = _load()
    if r.get("status") != "success":
        print(f"  ОШИБКА: {r.get('error')}")
        sys.exit(1)
    result = r.get("data", {}).get("result", [])
    if not result:
        print("  пусто — метрика ещё не собрана, подождите один интервал скрейпа (30s)")
        if len(sys.argv) > 2 and sys.argv[2] == "required":
            sys.exit(1)
        return
    for s in result[:10]:
        metric = s.get("metric", {})
        label = ", ".join(f"{k}={v}" for k, v in metric.items() if k in INTERESTING_LABELS)
        name = metric.get("__name__", "value")
        print(f"  {name}{{{label}}} = {s['value'][1]}")
    if len(result) > 10:
        print(f"  ... ещё {len(result) - 10} серий")


def loki_labels():
    r = _load()
    values = r.get("data", [])
    if not values:
        print("  метки не найдены — promtail ещё ничего не отправил")
        return
    print(f"  {len(values)} меток: {', '.join(values)}")


def loki_query():
    r = _load()
    if r.get("status") != "success":
        print(f"  ОШИБКА: {json.dumps(r, ensure_ascii=False)[:300]}")
        return
    streams = r.get("data", {}).get("result", [])
    if not streams:
        print("  логов не найдено за указанный интервал")
        return
    total = 0
    for stream in streams:
        labels = stream.get("stream", {})
        who = labels.get("pod") or labels.get("app") or labels.get("container") or "?"
        for _ts, line in stream.get("values", [])[:3]:
            total += 1
            print(f"  [{who}] {line[:160]}")
    print(f"  показано строк: {total} (потоков: {len(streams)})")


def grafana_rules():
    """Состояние provisioned-правил алертинга из /api/prometheus/grafana/api/v1/rules."""
    r = _load()
    groups = r.get("data", {}).get("groups", [])
    rules = [rule for g in groups for rule in g.get("rules", [])]
    hw = [rule for rule in rules if str(rule.get("labels", {}).get("hw")) == "11"]
    if not hw:
        print(f"  правил с меткой hw=11 не найдено (всего правил: {len(rules)})")
        return
    for rule in hw:
        print(f"  {rule.get('name')}: state={rule.get('state')} health={rule.get('health')}")
        for alert in rule.get("alerts", []) or []:
            print(f"    alert state={alert.get('state')} value={alert.get('value')}")


def grafana_contact_points():
    points = _load()
    if not points:
        print("  контактов не найдено")
        return
    for c in points:
        settings = c.get("settings", {})
        print(f"  {c.get('name')}: uid={c.get('uid')} type={c.get('type')} addresses={settings.get('addresses')}")


def grafana_firing():
    groups = _load().get("data", {}).get("groups", [])
    for group in groups:
        for rule in group.get("rules", []):
            uid = rule.get("uid") or rule.get("grafana_alert", {}).get("uid")
            matches = uid == "hw11-ingress-rps" or (
                rule.get("name") == "Ingress: RPS выше 1 запроса в секунду"
                and str(rule.get("labels", {}).get("hw")) == "11"
            )
            if matches and rule.get("state") == "firing":
                return
    sys.exit(1)


def grafana_test_body():
    """Тело запроса для POST /api/alertmanager/grafana/config/api/v1/receivers/test.

    На stdin — ответ GET /api/v1/provisioning/contact-points. uid существующей
    интеграции обязателен: по нему Grafana достаёт сохранённые secure settings,
    для неизвестного uid отвечает 400.
    """
    name = sys.argv[2] if len(sys.argv) > 2 else "email-hw11"
    points = _load()
    match = next((c for c in points if c.get("name") == name), None)
    if match is None:
        print(json.dumps({"error": f"contact point {name} not found"}, ensure_ascii=False))
        sys.exit(1)
    body = {
        "alert": {
            "labels": {"alertname": "hw11-test", "severity": "info", "hw": "11"},
            "annotations": {"summary": "Тестовое уведомление из hw-11"},
        },
        "receivers": [{
            "name": name,
            "grafana_managed_receiver_configs": [{
                "uid": match.get("uid"),
                "name": name,
                "type": match.get("type"),
                "settings": match.get("settings", {}),
                "secureSettings": {},
            }],
        }],
    }
    print(json.dumps(body, ensure_ascii=False))


MODES = {
    "prom-targets": prom_targets,
    "prom-query": prom_query,
    "loki-labels": loki_labels,
    "loki-query": loki_query,
    "grafana-rules": grafana_rules,
    "grafana-firing": grafana_firing,
    "grafana-contact-points": grafana_contact_points,
    "grafana-test-body": grafana_test_body,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in MODES:
        print(f"usage: render.py {{{'|'.join(MODES)}}} [arg]", file=sys.stderr)
        sys.exit(2)
    MODES[sys.argv[1]]()
