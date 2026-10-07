-- Наполняем requests данными, чтобы GET-эндпоинты под нагрузкой читали реальные строки,
-- а не пустую таблицу (пустой SELECT не даёт представления о времени ответа).
INSERT INTO requests (created_at)
SELECT now() - (s * interval '1 minute')
FROM generate_series(1, 5000) AS s
WHERE NOT EXISTS (SELECT 1 FROM requests);
