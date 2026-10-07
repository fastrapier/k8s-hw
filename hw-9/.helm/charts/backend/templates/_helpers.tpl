{{- define "backend.name" -}}
{{- .Chart.Name -}}
{{- end }}

{{- define "backend.fullname" -}}
{{- .Values.global.backend.serviceName | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "backend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "backend.labels" -}}
helm.sh/chart: {{ include "backend.chart" . }}
{{ include "backend.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: backend
app.kubernetes.io/part-of: hw9
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Подключение к Postgres. Один и тот же блок нужен Deployment, CronJob и Job
миграций — координаты берутся из ConfigMap сабчарта postgres, креды из его
Secret, поэтому backend не хранит ни адрес БД, ни пароль у себя.
*/}}
{{- define "backend.postgresEnv" -}}
- name: APP_POSTGRES_HOST
  valueFrom:
    configMapKeyRef:
      name: {{ .Values.global.postgres.configMapName }}
      key: host
- name: APP_POSTGRES_PORT
  valueFrom:
    configMapKeyRef:
      name: {{ .Values.global.postgres.configMapName }}
      key: port
- name: APP_POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.postgres.secretName }}
      key: username
- name: APP_POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.postgres.secretName }}
      key: password
- name: APP_POSTGRES_DB
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.postgres.secretName }}
      key: database
{{- end }}

{{/*
Образы werf: в сабчарте они доступны только через global,
в родительском чарте тот же образ виден как .Values.werf.image.<name>.
*/}}
{{- define "backend.image" -}}
{{- $name := index . 1 -}}
{{- $ctx := index . 0 -}}
{{- (index $ctx.Values.global.werf.images $name).ref -}}
{{- end }}
