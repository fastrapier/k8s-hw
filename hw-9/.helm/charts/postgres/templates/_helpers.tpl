{{/* Имя сабчарта */}}
{{- define "postgres.name" -}}
{{- .Chart.Name -}}
{{- end }}

{{/* Имя StatefulSet и Pod-ов */}}
{{- define "postgres.fullname" -}}
{{- .Values.global.postgres.serviceName | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "postgres.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgres.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "postgres.labels" -}}
helm.sh/chart: {{ include "postgres.chart" . }}
{{ include "postgres.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: database
app.kubernetes.io/part-of: hw9
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Порт БД одинаково нужен Service, StatefulSet и ConfigMap — берём из global,
чтобы backend знал его без дублирования значения.
*/}}
{{- define "postgres.port" -}}
{{- .Values.global.postgres.port | int -}}
{{- end }}
