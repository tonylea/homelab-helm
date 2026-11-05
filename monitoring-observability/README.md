# monitoring-observability

Metrics, logs and traces for the homelab, viewed in Grafana.

| Chart | What it does |
| --- | --- |
| [`observability-core`](observability-core) | Stores and queries metrics (Prometheus), logs (Loki) and traces (Tempo); Grafana on top |
| [`prometheus-operator-crds`](prometheus-operator-crds) | Prometheus Operator CRDs for clusters without observability-core, so the agent can scrape ServiceMonitors and PodMonitors there |
| [`observability-agent`](observability-agent) | Runs on each cluster: collects its metrics, logs, events and app telemetry and sends them to observability-core (Grafana Alloy, node-exporter, kube-state-metrics) |
| [`observability-gateway`](observability-gateway) | One per homelab, on k3s: receives syslog, agent pushes and OTLP from sources outside Kubernetes, scrapes non-Kubernetes targets, and sends it all to observability-core (Grafana Alloy) |

Upstream chart versions are pinned in each chart's `Chart.yaml`.

```text
observability-agent (each cluster)            observability-core
  alloy-receiver  OTLP from apps ─────traces──▶ Tempo ──────┐
  alloy-logs      pod + node logs ──────logs──▶ Loki        ├──▶ Grafana
  alloy-events    Kubernetes events ────logs──▶ Loki        │
  alloy-metrics   kubelet, cAdvisor, API ─────▶ Prometheus ─┘
                  server, CoreDNS, exporters

observability-gateway (k3s)
  alloy-gateway   syslog, agent pushes, OTLP, scrapes ──▶ Loki, Prometheus, Tempo
```

## observability-core

Built from these upstream charts:

- **kube-prometheus-stack:** Prometheus Operator, Prometheus, Alertmanager and
  Grafana. Prometheus picks up ServiceMonitors, PodMonitors, rules, probes and
  ScrapeConfigs from any release. Per-cluster collection is left to
  observability-agent: the chart's node-exporter, kube-state-metrics and its
  scraping of the kubelet, cAdvisor, API server and control plane are turned off.
  Its dashboards and alert rules stay, fed by the agent.
- **Loki:** monolithic mode (one replica) with filesystem storage.
- **Tempo:** single binary. Its metrics generator writes service-graph and span
  metrics into Prometheus.

The chart's own templates add:

- **Grafana datasources** for Loki and Tempo, linked to each other and to the
  Prometheus datasource (trace to logs, trace to metrics, service map, trace IDs in
  logs).
- **An ExternalSecret** for the Grafana admin login (see [Grafana admin
  login](#grafana-admin-login)).

### Endpoints

Service names are fixed with `fullnameOverride`, so they don't depend on the release
name.

| Service | Port | Used for |
| --- | --- | --- |
| `prometheus-stack-prometheus` | 9090 | Queries, remote write (`/api/v1/write`), OTLP metrics (`/api/v1/otlp/v1/metrics`) |
| `loki` | 3100 | Queries, push (`/loki/api/v1/push`), OTLP logs (`/otlp/v1/logs`) |
| `tempo` | 3200 | Queries |
| `tempo` | 4317 / 4318 | OTLP gRPC / HTTP |
| `grafana` | 80 | Grafana UI |

### Storage and retention

| Component | Volume | Retention |
| --- | --- | --- |
| Prometheus | 20Gi | 30 days or 18GB, whichever comes first |
| Loki | 50Gi | 30 days (720h) |
| Tempo | 25Gi | 14 days (336h) |
| Grafana | 5Gi | n/a |

Loki and Tempo only expire data by age, so their volume sizes aren't enforced limits.
Prometheus also has a size limit (`retentionSize`).

### Requests and limits

Every container has requests and limits, set in `values.yaml`. A comment next to each
says where its numbers come from: the component's docs, the upstream chart's example
values, a community report, or our own choice where nothing is published.

### Grafana admin login

Grafana reads its admin login from the Secret named in
`kube-prometheus-stack.grafana.admin.existingSecret` (default `grafana-admin`), with
the keys `admin-user` and `admin-password`. The chart never lets Grafana generate a
password, because a generated one changes on every render.

With `grafanaAdmin.externalSecret.enabled: true`, the chart renders an
`ExternalSecret` (`external-secrets.io/v1`) that creates that Secret from 1Password:

- Store: ClusterSecretStore `onepassword` (`grafanaAdmin.externalSecret.secretStoreRef`).
- Source: item `grafana-admin`, fields `username` and `password`
  (`grafanaAdmin.externalSecret.remoteRefs`), in the 1Password SDK provider's
  `<item>/<field>` key format.

### Cluster overrides

| File | Overrides |
| --- | --- |
| `values-minikube.yaml` | Turns on the 1Password ExternalSecret. Puts all four volumes on the `observability-ssd` storage class. Adds `nginx` ingresses for `grafana`, `prometheus` and `alertmanager` under `internal.deadrobot.co.uk`. Labels what Prometheus scrapes itself with `cluster: minikube`, matching the agent's data. Sends Grafana's own traces to the agent's OTLP receiver. Exposes ingest endpoints for other clusters' agents: Loki push paths on `loki`, Prometheus remote write on `prometheus`, and Tempo OTLP traces on `tempo` (`tempoOtlpIngress`), all under `internal.deadrobot.co.uk`. |

## prometheus-operator-crds

The Prometheus Operator CRDs (ServiceMonitor, PodMonitor, PrometheusRule and the rest),
from the upstream `prometheus-operator-crds` chart, pinned to the same operator version
as observability-core's kube-prometheus-stack. Install it on clusters that run the agent
but not observability-core, before the agent. Not needed where observability-core runs:
kube-prometheus-stack installs the same CRDs. The CRDs are too large for a client-side
apply, so Argo CD needs server-side apply for it.

## observability-agent

One install per cluster. Four Grafana Alloy instances, laid out as in Grafana's
k8s-monitoring chart, plus node-exporter and kube-state-metrics. Each Alloy config is
generated by `templates/alloy-*-config.yaml`.

| Collector | Runs as | Collects |
| --- | --- | --- |
| `alloy-logs` | DaemonSet, including control-plane nodes | Pod logs from its node's `/var/log/pods`; node logs from the systemd journal |
| `alloy-receiver` | Deployment, 1 replica | OTLP from apps on the `alloy-receiver` Service (4317 gRPC, 4318 HTTP): traces to Tempo, metrics to Prometheus, logs to Loki |
| `alloy-events` | Deployment, 1 replica | Kubernetes events |
| `alloy-metrics` | StatefulSet, clustered | kubelet, cAdvisor, API server, CoreDNS, node-exporter, kube-state-metrics; ServiceMonitors and PodMonitors |

Metrics use the job labels kube-prometheus-stack's dashboards and alerts expect
(`kubelet`, `apiserver`, `coredns`, `node-exporter`, `kube-state-metrics`).

| Value | Meaning |
| --- | --- |
| `cluster` | Required. Added as the `cluster` label (and `k8s.cluster.name` on OTLP data) to everything the agent sends. |
| `endpoints.loki` | Loki base URL. The chart appends `/loki/api/v1/push` and `/otlp`. |
| `endpoints.prometheus` | Prometheus base URL. The chart appends `/api/v1/write`. |
| `endpoints.tempoOtlpGrpc` | Tempo OTLP gRPC `host:port`, for an agent in the same cluster as observability-core. |
| `endpoints.tempoOtlpHttp` | Tempo OTLP HTTP base URL, for agents on other clusters going through the ingress. The chart appends `/v1/traces`. Used instead of `tempoOtlpGrpc` when set. |
| `collect.podLogs` | Pod logs. |
| `collect.nodeLogs` | Node logs from the systemd journal. `nodeLogs.journalPath` picks the directory; empty (the default) reads both `/var/log/journal` and `/run/log/journal`. |
| `collect.events` | Kubernetes events. |
| `collect.otlp` | OTLP from apps. |
| `collect.clusterMetrics` | kubelet, cAdvisor, API server and CoreDNS metrics; also deploys and scrapes node-exporter and kube-state-metrics. |
| `collect.serviceMonitors` | Targets from ServiceMonitors and PodMonitors. Needs the Prometheus Operator CRDs. |

An endpoint is only required when a `collect` option that uses it is on.

### Cluster overrides

| File | Overrides |
| --- | --- |
| `values-k3s.yaml` | `cluster: k3s`; sends to observability-core's ingest hosts under `internal.deadrobot.co.uk` over HTTP. ServiceMonitor/PodMonitor scraping on (needs `prometheus-operator-crds` installed first), with ServiceMonitors for the Alloy collectors. |
| `values-minikube.yaml` | `cluster: minikube`; endpoints point at observability-core in the `observability` namespace. Node logs off. ServiceMonitor/PodMonitor scraping off, since observability-core's Prometheus already does it there; the Alloy collectors get ServiceMonitors so it scrapes them too. |

## observability-gateway

One Grafana Alloy instance (`alloy-gateway`, one replica) for everything that isn't a
Kubernetes cluster: network devices, servers, Home Assistant and the like. It follows
OpenTelemetry's agent-and-gateway pattern: clusters run observability-agent, and other
sources go through the gateway. It runs on k3s and sends to observability-core over the
same ingest hosts as the k3s agent.

| Input | How sources reach it | Configured by |
| --- | --- | --- |
| Loki push (`/loki/api/v1/push`) | Ingress | Always on |
| Prometheus remote write (`/api/v1/metrics/write`) | Ingress | Always on |
| OTLP over HTTP (`/v1/traces`, `/v1/metrics`, `/v1/logs`) | Ingress | Always on |
| Syslog | `alloy-gateway-syslog`, a MetalLB LoadBalancer Service with `externalTrafficPolicy: Local` so senders' IPs are kept | `syslog.listeners` |
| Scrapes | The gateway pulls from each target | `scrape.targets` |

Nothing the gateway sends has a `cluster` label. Sources are told apart by name, never
by IP:

- **Syslog:** `job` comes from the listener (e.g. `syslog/unifi`). `host` is the
  hostname in the message; if there is none, the sender's reverse-DNS name; failing
  that, its IP. The sender's IP, severity (`level`), facility and app name are stored
  as structured metadata, so each line can be filtered on them without them becoming
  stream labels.
- **Scrapes:** `job` comes from the target entry and `instance` is the target's DNS
  name and port.
- **Agent pushes:** keep the labels the agent set (e.g. `job` and `instance` from a
  server's node-exporter).

| Value | Meaning |
| --- | --- |
| `endpoints.*` | observability-core base URLs, as for observability-agent. |
| `ingress.enabled`, `className`, `host`, `annotations` | Ingress for the HTTP inputs. |
| `syslog.listeners` | One entry per port and format: `name`, `port`, `protocol` (`udp`/`tcp`), `format` (`rfc5424`, `rfc3164` or `raw`) and `job`. Alloy listens on `port` + 10000 in the pod, so ports below 1024 need no privileges. |
| `syslog.service.loadBalancerIP` | Fixed IP for the syslog Service, set as MetalLB's `metallb.io/loadBalancerIPs` annotation. Empty lets MetalLB pick. |
| `scrape.targets` | One entry per job: `job`, `addresses` (`host:port`, by DNS name), optional `metricsPath`, `scheme` and `bearerTokenSecret` (`name` and `key` of a Secret in the release namespace). |
| `scrape.interval` | How often targets are scraped. Default `30s`. |

The gateway's RBAC is limited to reading Secrets in the `observability` namespace, for
scrape credentials.

### Cluster overrides

| File | Overrides |
| --- | --- |
| `values-k3s.yaml` | Sends to observability-core's ingest hosts under `internal.deadrobot.co.uk` over HTTP. Ingress on `gateway.internal.deadrobot.co.uk` through k3s's Traefik (`platform-traefik`). ServiceMonitor on, so the k3s agent scrapes the gateway. No listeners or scrape targets yet: each source adds its own. |

## Tests

| What | Where | Checks |
| --- | --- | --- |
| Unit tests | `observability-core/tests/*_test.yaml` | Datasource provisioning and linking; the ExternalSecret's name, keys and store; the Tempo OTLP ingress |
| Unit tests | `observability-agent/tests/*_test.yaml` | Generated Alloy configs: endpoints, cluster label, job labels, node filtering, toggles, required values |
| Alloy validation | `observability-agent/tests/validate-alloy-config.sh` | Runs `alloy validate` (same Alloy version as the subcharts, via Docker) on every collector's config rendered from each values file |
| Unit tests | `observability-gateway/tests/*_test.yaml` | Gateway config: endpoints, no cluster label, input ports, syslog listeners and host labelling, scrape targets and credentials; the syslog Service and the ingress |
| Alloy validation | `observability-gateway/tests/validate-alloy-config.sh` | Runs `alloy validate` on the gateway config rendered from each values file |
| End-to-end tests | `tests/end-to-end-tests.sh` | Installs both charts with their `ci/` values, sends a trace, a metric and a log through the agent over OTLP, and checks they arrive in Tempo, Prometheus and Loki. Also checks pod logs and events reach Loki; kubelet, cAdvisor, API server, CoreDNS, node-exporter and kube-state-metrics metrics and Tempo span metrics reach Prometheus; and Grafana has all three datasources. |

`tests/end-to-end-tests.sh` installs releases named `observability-core` and `observability-agent` into the `observability`
namespace of your current kubectl context. Only run it against a disposable cluster.
