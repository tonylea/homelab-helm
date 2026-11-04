{{- define "agent.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monitoring-observability
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{- define "agent.endpoint" -}}
{{- $v := index .ctx.Values.endpoints .name -}}
{{- required (printf "endpoints.%s is required" .name) $v | trimSuffix "/" -}}
{{- end }}
