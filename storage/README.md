# storage

Storage for the homelab clusters.

| Chart | What it does |
| --- | --- |
| [`local-path-provisioner`](local-path-provisioner) | Creates volumes on demand as folders under a base path on the node |

Upstream chart versions are pinned in each chart's `Chart.yaml`.

## local-path-provisioner

Built from [rancher/local-path-provisioner](https://github.com/rancher/local-path-provisioner),
using the upstream chart as republished unchanged by containeroo (`charts.containeroo.ch`),
because rancher only publishes the chart in its git repository.

When a claim asks for the `observability-ssd` StorageClass, the provisioner creates a folder
for it under the base path and mounts it into the pod as a `hostPath` volume.

| Setting | Value |
| --- | --- |
| StorageClass | `observability-ssd`, not the cluster default |
| Reclaim policy | `Delete`: deleting a claim deletes its folder and data |
| Binding | `WaitForFirstConsumer`: the volume is created when a pod using the claim is scheduled |
| Capacity | Not enforced. The size in a claim is ignored. |
| Helper image | `busybox:1.38.0`, runs briefly to create or remove a volume's folder |

Requests and limits are set for both the provisioner and the helper pod in `values.yaml`.

### Cluster overrides

| File | Overrides |
| --- | --- |
| `values-minikube.yaml` | Base path `/mnt/observability`, the SSD folder bound into the minikube node |

## Tests

| What | Where | Checks |
| --- | --- | --- |
| Unit tests | `local-path-provisioner/tests/*_test.yaml` | StorageClass name, default flag, reclaim policy and binding mode; minikube base path; pinned helper image; requests and limits |
