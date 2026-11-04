#!/usr/bin/env bash
# End-to-end tests for monitoring-observability: installs stack + agent with their
# ci/ values into the current kubectl context, sends one trace, one metric and one
# log through the agent over OTLP, and checks each lands in Tempo, Prometheus and
# Loki. Also checks the agent ships pod logs and Grafana has its datasources.
#
# Meant for a throwaway cluster (CI creates one with kind). Needs: helm, kubectl,
# curl, jq, openssl, and chart dependencies built.
set -euo pipefail

area="$(cd "$(dirname "$0")/.." && pwd)"
ns=monitoring
timeout_s=${E2E_QUERY_TIMEOUT:-180}
run_id="$(openssl rand -hex 6)"
trace_id="$(openssl rand -hex 16)"
span_id="$(openssl rand -hex 8)"
now_ns="$(date +%s)000000000"
pf_pids=()

log() { printf '\n==> %s\n' "$*"; }

cleanup() {
  local status=$?
  for pid in "${pf_pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  if [[ $status -ne 0 ]]; then
    log "FAILED, cluster state for debugging"
    kubectl -n "$ns" get pods -o wide || true
    kubectl -n "$ns" get events --sort-by=.lastTimestamp | tail -30 || true
    for pod in $(kubectl -n "$ns" get pods -o name); do
      echo "--- $pod"
      kubectl -n "$ns" logs "$pod" --all-containers --tail=30 || true
    done
  fi
}
trap cleanup EXIT

# Retries a check until it passes or the timeout runs out.
eventually() {
  local desc=$1; shift
  local deadline=$((SECONDS + timeout_s))
  until "$@" >/dev/null 2>&1; do
    if ((SECONDS > deadline)); then
      echo "FAIL: $desc (after ${timeout_s}s)"
      return 1
    fi
    sleep 5
  done
  echo "ok: $desc"
}

port_forward() {
  kubectl -n "$ns" port-forward "svc/$1" "$2:$3" >/dev/null 2>&1 &
  pf_pids+=($!)
}

log "Installing stack and agent (run ${run_id})"
helm upgrade --install stack "$area/stack" -n "$ns" --create-namespace \
  -f "$area/stack/ci/default-values.yaml" --wait --timeout 10m
helm upgrade --install agent "$area/agent" -n "$ns" \
  -f "$area/agent/ci/default-values.yaml" --wait --timeout 5m
kubectl -n "$ns" rollout status statefulset/loki statefulset/tempo --timeout 5m
kubectl -n "$ns" wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus --timeout 5m

port_forward alloy-agent 14318 4318
port_forward prometheus-stack-prometheus 19090 9090
port_forward loki 13100 3100
port_forward tempo 13200 3200
port_forward grafana 13000 80
eventually "port-forwards up" curl -fsS http://localhost:13100/ready

resource='{"attributes":[{"key":"service.name","value":{"stringValue":"end-to-end-test"}}]}'

send_otlp() {
  curl -fsS -X POST "http://localhost:14318/v1/$1" -H 'Content-Type: application/json' -d "$2"
}

log "Sending OTLP trace, metric and log through the agent"
send_otlp traces "{\"resourceSpans\":[{\"resource\":$resource,\"scopeSpans\":[{\"spans\":[{
  \"traceId\":\"$trace_id\",\"spanId\":\"$span_id\",\"name\":\"end-to-end-test\",\"kind\":1,
  \"startTimeUnixNano\":\"$now_ns\",\"endTimeUnixNano\":\"$now_ns\"}]}]}]}"
send_otlp metrics "{\"resourceMetrics\":[{\"resource\":$resource,\"scopeMetrics\":[{\"metrics\":[{
  \"name\":\"end_to_end_test_runs\",\"gauge\":{\"dataPoints\":[{\"asDouble\":1,\"timeUnixNano\":\"$now_ns\",
  \"attributes\":[{\"key\":\"run_id\",\"value\":{\"stringValue\":\"$run_id\"}}]}]}}]}]}]}"
send_otlp logs "{\"resourceLogs\":[{\"resource\":$resource,\"scopeLogs\":[{\"logRecords\":[{
  \"timeUnixNano\":\"$now_ns\",\"severityText\":\"INFO\",\"body\":{\"stringValue\":\"end-to-end test $run_id\"}}]}]}]}"

prom_has() {
  curl -fsS http://localhost:19090/api/v1/query --data-urlencode "query=$1" \
    | jq -e '.data.result | length > 0'
}

loki_has() {
  curl -fsS -G http://localhost:13100/loki/api/v1/query_range --data-urlencode "query=$1" --data-urlencode "limit=1" \
    | jq -e '.data.result | length > 0'
}

grafana_has_datasource() {
  curl -fsS -u admin:ci-only-password "http://localhost:13000/api/datasources/uid/$1" | jq -e ".uid == \"$1\""
}

log "Checking data arrived"
failed=0
eventually "trace in Tempo" curl -fsS "http://localhost:13200/api/traces/$trace_id" || failed=1
eventually "OTLP metric in Prometheus with cluster label" \
  prom_has "end_to_end_test_runs{run_id=\"$run_id\",cluster=\"ci\"}" || failed=1
eventually "OTLP log in Loki" loki_has "{service_name=\"end-to-end-test\"} |= \"$run_id\"" || failed=1
eventually "pod logs in Loki with cluster label" loki_has "{cluster=\"ci\",namespace=\"$ns\"}" || failed=1
eventually "Kubernetes events in Loki" loki_has "{cluster=\"ci\",job=\"integrations/kubernetes/eventhandler\"}" || failed=1
eventually "Tempo span metrics in Prometheus" prom_has 'traces_spanmetrics_calls_total{service="end-to-end-test"}' || failed=1
for uid in prometheus loki tempo; do
  eventually "Grafana datasource $uid" grafana_has_datasource "$uid" || failed=1
done

exit "$failed"
