#!/usr/bin/env bash
# End-to-end tests for networking: installs metallb, then metallb-pools, with their ci/
# values into the current kubectl context. Checks a LoadBalancer Service that asks for
# a pool IP gets it, and one that doesn't ask stays pending (autoAssign is off).
#
# Meant for a throwaway cluster (CI creates one with kind). Needs: helm, kubectl, jq,
# and chart dependencies built.
set -euo pipefail

area="$(cd "$(dirname "$0")/.." && pwd)"
ns=metallb-system
test_ns=networking-e2e
timeout_s=${E2E_QUERY_TIMEOUT:-120}
pinned_ip=192.0.2.51

log() { printf '\n==> %s\n' "$*"; }

cleanup() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    log "FAILED, cluster state for debugging"
    kubectl -n "$ns" get pods -o wide || true
    kubectl -n "$test_ns" get svc -o wide || true
    kubectl -n "$test_ns" get events --sort-by=.lastTimestamp | tail -20 || true
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

log "Installing metallb and metallb-pools"
helm upgrade --install networking-metallb "$area/metallb" -n "$ns" --create-namespace \
  -f "$area/metallb/ci/default-values.yaml" --wait --timeout 5m
kubectl -n "$ns" rollout status daemonset/metallb-speaker --timeout 5m
helm upgrade --install networking-metallb-pools "$area/metallb-pools" -n "$ns" \
  -f "$area/metallb-pools/ci/default-values.yaml" --wait --timeout 2m

log "Creating LoadBalancer Services"
kubectl create namespace "$test_ns" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "$test_ns" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: pinned
  annotations:
    metallb.io/loadBalancerIPs: ${pinned_ip}
spec:
  type: LoadBalancer
  selector:
    app: none
  ports:
    - port: 80
---
apiVersion: v1
kind: Service
metadata:
  name: unpinned
spec:
  type: LoadBalancer
  selector:
    app: none
  ports:
    - port: 80
EOF

ingress_ips() {
  kubectl -n "$test_ns" get svc "$1" -o json | jq -r '[.status.loadBalancer.ingress[]?.ip] | join(",")'
}

has_pinned_ip() { [[ "$(ingress_ips pinned)" == "$pinned_ip" ]]; }

# The controller records an AllocationFailed event when no pool will auto-assign.
unpinned_refused() {
  kubectl -n "$test_ns" get events -o json \
    --field-selector involvedObject.name=unpinned,reason=AllocationFailed \
    | jq -e '.items | length > 0'
}

log "Checking IP assignment"
failed=0
eventually "Service asking for ${pinned_ip} gets it" has_pinned_ip || failed=1
eventually "Service without a requested IP is refused one" unpinned_refused || failed=1
if [[ -n "$(ingress_ips unpinned)" ]]; then
  echo "FAIL: Service without a requested IP got $(ingress_ips unpinned)"
  failed=1
fi

exit "$failed"
