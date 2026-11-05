# networking

Getting traffic from the home network into the clusters.

| Chart | What it does |
| --- | --- |
| [`metallb`](metallb) | MetalLB: gives LoadBalancer Services an IP on the node network, announced over ARP (L2 mode) |
| [`metallb-pools`](metallb-pools) | The address pool MetalLB hands IPs out from, and its L2 advertisement |

They are separate charts because `metallb` installs MetalLB's CRDs and admission
webhook as templates: a pool in the same Helm release would fail to install. Install
`metallb` first, then `metallb-pools`, both into the `metallb-system` namespace.

Upstream chart versions are pinned in each chart's `Chart.yaml`.

## metallb

Built from the [MetalLB](https://metallb.universe.tf) chart. It runs the controller
(one replica), which assigns IPs from the pool, and the speaker (a DaemonSet on every
node, including control-plane nodes), which answers ARP for them. k3s's own load
balancer (ServiceLB) must be off for MetalLB to work, and it is off on k3s.

| Setting | Value |
| --- | --- |
| Mode | Native, L2 only. Neither FRR backend runs: FRR-K8s (the upstream default) and FRR mode are only needed for BGP. |
| Names | `metallb-controller` and `metallb-speaker`, whatever the release is called |
| Metrics | HTTPS on port 9120, authorised against Kubernetes RBAC. The scraper needs `get` on the `/metrics` URL, which observability-agent's `alloy-metrics` already has. |

Requests and limits for the controller and speaker are set in `values.yaml`, sized from
what MetalLB used on k3s.

### Cluster overrides

| File | Overrides |
| --- | --- |
| `values-k3s.yaml` | ServiceMonitors for the controller and speaker, scraped by observability-agent |

## metallb-pools

One IPAddressPool and an L2Advertisement for it, both named after `pool.name`.

| Value | Default | Meaning |
| --- | --- | --- |
| `pool.name` | `default-pool` | Name of the IPAddressPool and the L2Advertisement |
| `pool.addresses` | none, required | Ranges (`a.b.c.d-a.b.c.e`) or CIDRs MetalLB may hand out |
| `pool.autoAssign` | `false` | When `false`, a Service only gets the IP it asks for (below). One that doesn't ask stays pending. |

With auto-assign off, IPs never change under DNS records. A Service asks for its IP with
an annotation:

```yaml
metadata:
  annotations:
    metallb.io/loadBalancerIPs: 192.168.30.51
```

### Cluster overrides

| File | Overrides |
| --- | --- |
| `values-k3s.yaml` | `192.168.30.50-192.168.30.59` on V30 |

Addresses in the k3s pool:

| IP | Used by |
| --- | --- |
| `192.168.30.50` | Kept for Traefik |
| `192.168.30.51` | `alloy-gateway-lb` (observability-gateway) |
| `192.168.30.52`–`.59` | Spare |

## Tests

| What | Where | Checks |
| --- | --- | --- |
| Unit tests | `metallb/tests/*_test.yaml` | No FRR containers; fixed names; requests and limits; ServiceMonitors only with `values-k3s.yaml`, without MetalLB's extra scraper RBAC |
| Unit tests | `metallb-pools/tests/*_test.yaml` | Pool kind, name and namespace; auto-assign off; k3s range; addresses required and validated; L2Advertisement follows the pool name |
| End-to-end | `tests/end-to-end-tests.sh` | Installs both charts, then checks a Service asking for a pool IP gets it and one that doesn't ask is refused |
