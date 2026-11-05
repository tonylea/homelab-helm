{{- define "observability-gateway.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monitoring-observability
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{- define "observability-gateway.endpoint" -}}
{{- $v := index .ctx.Values.endpoints .name -}}
{{- required (printf "endpoints.%s is required" .name) $v | trimSuffix "/" -}}
{{- end }}

{{/* Labels the Alloy subchart puts on the gateway pods, for the syslog Service. Its
name label is the dependency alias in Chart.yaml. */}}
{{- define "observability-gateway.alloySelector" -}}
app.kubernetes.io/name: alloy-gateway
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Port Alloy listens on inside the pod for a syslog listener. */}}
{{- define "observability-gateway.syslogContainerPort" -}}
{{- add 10000 .port -}}
{{- end }}

{{/* Alloy component label for a scrape job, e.g. my-app -> my_app. */}}
{{- define "observability-gateway.componentId" -}}
{{- regexReplaceAll "[^a-zA-Z0-9_]" . "_" -}}
{{- end }}
