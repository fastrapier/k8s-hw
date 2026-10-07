{{/*
Общие labels для ресурсов API.
*/}}
{{- define "backend.labels" -}}
app.kubernetes.io/name: api
app.kubernetes.io/component: api
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "backend.selectorLabels" -}}
app.kubernetes.io/name: api
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Env-блок с реквизитами Postgres — одинаковый у Deployment, Job миграций и CronJob.
*/}}
{{- define "backend.postgresEnv" -}}
- name: APP_POSTGRES_HOST
  valueFrom:
    configMapKeyRef:
      name: postgres-config
      key: host
- name: APP_POSTGRES_PORT
  valueFrom:
    configMapKeyRef:
      name: postgres-config
      key: port
- name: APP_POSTGRES_DB
  valueFrom:
    secretKeyRef:
      name: postgres-credentials
      key: POSTGRES_DB
- name: APP_POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: postgres-credentials
      key: POSTGRES_USER
- name: APP_POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-credentials
      key: POSTGRES_PASSWORD
{{- end }}
