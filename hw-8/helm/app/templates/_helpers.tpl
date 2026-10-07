{{- define "hw8-app.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "hw8-app.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{- define "hw8-app.tag" -}}
{{- required "image.tag обязателен: передайте --set image.tag=<версия из semantic-release>" .Values.image.tag -}}
{{- end -}}

{{- define "hw8-app.labels" -}}
app.kubernetes.io/name: {{ include "hw8-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ include "hw8-app.tag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "hw8-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hw8-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
