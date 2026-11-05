{{- define "observability-agent.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monitoring-observability
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{- define "observability-agent.cluster" -}}
{{- required "cluster is required" .Values.cluster -}}
{{- end }}

{{- define "observability-agent.endpoint" -}}
{{- $v := index .ctx.Values.endpoints .name -}}
{{- required (printf "endpoints.%s is required" .name) $v | trimSuffix "/" -}}
{{- end }}

{{/* ConfigMap holding one collector's config. Args: ctx, collector (values key), body. */}}
{{- define "observability-agent.configMap" -}}
{{- $alloy := (index .ctx.Values .collector).alloy -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $alloy.configMap.name }}
  labels:
    {{- include "observability-agent.labels" .ctx | nindent 4 }}
data:
  {{ $alloy.configMap.key }}: |
    logging {
      level  = "info"
      format = "logfmt"
    }
    {{- .body | nindent 4 }}
{{- end }}

{{- define "observability-agent.lokiWrite" -}}
loki.write "default" {
  endpoint {
    url = "{{ include "observability-agent.endpoint" (dict "ctx" . "name" "loki") }}/loki/api/v1/push"
  }
  external_labels = {
    cluster = "{{ include "observability-agent.cluster" . }}",
  }
}
{{- end }}

{{- define "observability-agent.remoteWrite" -}}
prometheus.remote_write "default" {
  endpoint {
    url = "{{ include "observability-agent.endpoint" (dict "ctx" . "name" "prometheus") }}/api/v1/write"
  }
  external_labels = {
    cluster = "{{ include "observability-agent.cluster" . }}",
  }
}
{{- end }}
