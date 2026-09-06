{{- define "ingress-metrics.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ingress-metrics.fullname" -}}
{{- $name := include "ingress-metrics.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "ingress-metrics.labels" -}}
app.kubernetes.io/name: {{ include "ingress-metrics.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "ingress-metrics.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ingress-metrics.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
