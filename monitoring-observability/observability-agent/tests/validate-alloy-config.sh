#!/usr/bin/env bash
# Renders every collector's Alloy config for every values file the chart ships with
# and checks it with `alloy validate`, using the Alloy version the subcharts deploy.
# Catches unknown components, bad arguments and broken wiring that template tests
# can't see. Needs: helm, docker, dependencies built (helm dependency build).
set -euo pipefail

chart_dir="$(cd "$(dirname "$0")/.." && pwd)"
alloy_version="$(helm show chart "$chart_dir"/charts/alloy-*.tgz | awk '/^appVersion:/ {print $2}')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for values in "$chart_dir"/values-*.yaml "$chart_dir"/ci/*-values.yaml; do
  name="$(basename "$values" .yaml)"
  for template in "$chart_dir"/templates/alloy-*-config.yaml; do
    collector="$(basename "$template" -config.yaml)"
    helm template agent "$chart_dir" -f "$values" --show-only "templates/$(basename "$template")" \
      | awk 'f { sub(/^    /, ""); print } /config.alloy: \|/ { f = 1 }' > "$work/$name-$collector.alloy"
    echo "alloy ${alloy_version} validate: ${values#"$chart_dir"/} ${collector}"
    docker run --rm -v "$work:/cfg:ro" "grafana/alloy:${alloy_version}" validate "/cfg/$name-$collector.alloy"
  done
done
