#!/usr/bin/env bash
# Checks every dashboard in dashboards/ only queries observability-core's Prometheus
# datasource (uid "prometheus"): no import inputs (${DS_...}) or other datasource uids
# left from upstream. Needs: jq.
set -euo pipefail

dir="$(cd "$(dirname "$0")/.." && pwd)/dashboards"
failed=0
shopt -s nullglob
files=("$dir"/*.json)
if ((${#files[@]} == 0)); then
  echo "FAIL: no dashboards in $dir"
  exit 1
fi

for f in "${files[@]}"; do
  bad="$(jq -r '[.. | objects | select(has("datasource")) | .datasource | objects
                 | select(.type != "datasource" and .uid != "prometheus") | .uid]
                | unique | join(", ")' "$f")"
  if [[ -n "$bad" ]] || grep -q '\${DS_' "$f"; then
    echo "FAIL: $(basename "$f") uses other datasources: ${bad:-\${DS_...\} input}"
    failed=1
  else
    echo "ok: $(basename "$f")"
  fi
done

exit "$failed"
