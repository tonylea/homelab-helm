#!/usr/bin/env bash
# Fetches unpoller's Prometheus dashboards from github.com/unpoller/dashboards (MIT) at
# a pinned commit into dashboards/, pointing every Prometheus datasource reference at
# observability-core's datasource (uid "prometheus"). Upstream uses an import input
# (${DS_PROMETHEUS}), plus an undefined input and a hard-coded uid on some rows.
#
# To update: change the commit below, run this script, and review the diff.
# Needs: curl, jq.
set -euo pipefail

commit=adbe342f09d0fe06b1cc152d28ab0bae5ee3d8b9
datasource_uid=prometheus
out="$(cd "$(dirname "$0")" && pwd)/dashboards"

# file name in this chart = upstream dashboard name
dashboards=(
  "network-sites=Network Sites"
  "usw-insights=USW Insights"
  "uap-insights=UAP Insights"
  "usg-insights=USG Insights"
  "client-insights=Client Insights"
)

rm -f "$out"/*.json
for entry in "${dashboards[@]}"; do
  file=${entry%%=*}
  name="UniFi-Poller_ ${entry#*=} - Prometheus.json"
  curl -fsSL "https://raw.githubusercontent.com/unpoller/dashboards/${commit}/v2.0.0/${name// /%20}" \
    | jq --arg uid "$datasource_uid" '
        del(.__inputs, .id)
        | walk(if type == "object" and (.datasource? | type) == "object"
                 and ((.datasource.uid // "") | test("^\\$\\{DS_|^bdkj55oguty4gd$"))
               then .datasource = {type: "prometheus", uid: $uid}
               else . end)' \
    > "$out/$file.json"
  echo "$file.json"
done
