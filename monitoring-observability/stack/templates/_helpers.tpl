{{- define "stack.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monitoring-observability
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{- define "stack.grafanaAdminSecret" -}}
{{- (index .Values "kube-prometheus-stack" "grafana" "admin" "existingSecret") | required "kube-prometheus-stack.grafana.admin.existingSecret is required" -}}
{{- end }}
