{{- define "locust.labels" -}}
app.kubernetes.io/name: locust
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Имя пода мастера, которое оператор ставит в label performance-test-pod-name.
По этому label находит воркеры и наш Service для web UI.
*/}}
{{- define "locust.masterPodName" -}}
{{- printf "%s-master" .Values.name }}
{{- end }}

{{/*
URL приложения под нагрузкой.
*/}}
{{- define "locust.targetHost" -}}
{{- if .Values.target.host }}
{{- .Values.target.host }}
{{- else }}
{{- printf "http://%s.%s.svc.cluster.local:%v" .Values.target.service .Release.Namespace .Values.target.port }}
{{- end }}
{{- end }}

{{/*
Путь к locustfile внутри пода: /lotest/src — дефолтный srcMountPath оператора,
куда монтируется ConfigMap целиком (каждый ключ становится файлом).
*/}}
{{- define "locust.locustfilePath" -}}
{{- print "/lotest/src/locustfile.py" }}
{{- end }}
