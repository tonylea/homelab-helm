# homelab-helm

## Areas

Charts are grouped into area folders. Each area has its own README with what its
charts do and how to configure them.

| Area                                                           | Charts                                                                                           | What it does                                               |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| [gitops](gitops/README.md)                                     | `argocd-clusters`                                                                                | Argo CD configuration: the external clusters it deploys to |
| [monitoring-observability](monitoring-observability/README.md) | `observability-core`, `observability-agent`, `observability-gateway`, `prometheus-operator-crds` | Metrics, logs and traces: storage, querying and collection |
| [networking](networking/README.md)                             | `metallb`, `metallb-pools`                                                                       | LoadBalancer IPs on the home network                       |
| [secrets-management](secrets-management/README.md)             | `external-secrets`, `onepassword-store`                                                          | Kubernetes Secrets created from 1Password                  |
| [storage](storage/README.md)                                   | `local-path-provisioner`                                                                         | Volumes created on demand under a base path on the node    |

## Layout

```text
<area>/
  README.md                 # what the area's charts do and how to configure them
  <chart>/
    Chart.yaml  Chart.lock
    values.yaml             # defaults
    values-<cluster>.yaml   # per-cluster overrides
    values.schema.json      # validates values at render time
    templates/
    ci/*-values.yaml        # values used by CI
    tests/*_test.yaml       # helm-unittest suites
    tests/*.sh              # optional extra checks, run by CI
  tests/end-to-end-tests.sh # optional end-to-end tests across the area's charts
```

## CI

Every pull request to `main` runs `.github/workflows/pull-request-checks.yaml`, which
runs three stages in order. Each stage only starts if the one before it passed, and the
`Pull request checks result` job passes only when all three did.

```text
Lint ──▶ Chart static tests ──▶ Chart end-to-end tests
```

### 1. Lint (`.github/workflows/lint.yaml`)

Three jobs in parallel:

- **Markdown lint:** every `*.md` file, with markdownlint-cli2. Rules are in
  `.markdownlint-cli2.yaml`.
- **Spell check:** every file, with cspell. Settings and project-specific words are in
  `cspell.config.yaml`.
- **Chart lint:** `ct lint` on every chart that changed: Helm lint against each
  `ci/*-values.yaml`, YAML lint, and the chart version bump check.

### 2. Chart static tests (`.github/workflows/chart-static-tests.yaml`)

For every chart that changed, as reported by `ct list-changed`:

1. `helm unittest`: the chart's `tests/*_test.yaml`.
2. Render with every `values-*.yaml` and `ci/*-values.yaml`, then validate the
   manifests with `kubeconform` (Kubernetes schemas plus CRD schemas from the
   [datreeio CRDs catalog](https://github.com/datreeio/CRDs-catalog)).
3. Every executable `tests/*.sh` in the chart.

### 3. Chart end-to-end tests (`.github/workflows/chart-end-to-end-tests.yaml`)

Runs an area's `tests/end-to-end-tests.sh` on a throwaway kind cluster, only when the
PR changes one of:

- `<area>/<chart>/Chart.yaml`
- `<area>/<chart>/Chart.lock`
- `<area>/<chart>/templates/**`
- `<area>/tests/**`

Adding the `run-end-to-end-tests` label to a PR runs them for any change in an area.
Values-only changes skip them.

Tool versions (Helm, helm-unittest, kubeconform, and the Kubernetes version manifests
are validated against) are set in the `env` block at the top of each workflow.

## Adding a chart

1. Create `<area>/<chart>/` following the layout above.
2. For a new area, add the folder to `chart-dirs` in [`ct.yaml`](ct.yaml). CI
   ignores charts in areas that aren't listed.
3. If a dependency comes from a repository not yet in `chart-repos` in `ct.yaml`,
   add it there.
4. Run `helm dependency update <area>/<chart>` and commit `Chart.lock`.
5. Add at least one `ci/*-values.yaml` and unit tests for the chart's own templates.
6. Optionally add `<area>/tests/end-to-end-tests.sh`. CI runs it when present.
7. Add the area to the table above, and describe the chart in the area's README.

## Running checks locally

Needs Helm 4, the [helm-unittest](https://github.com/helm-unittest/helm-unittest)
plugin, and Node.js for the linters.

```sh
npx markdownlint-cli2
npx cspell --dot "**"
helm dependency build <area>/<chart>
helm lint <area>/<chart> -f <area>/<chart>/values-<cluster>.yaml
helm unittest <area>/<chart>
helm template test <area>/<chart> -f <area>/<chart>/values-<cluster>.yaml
```

`<area>/tests/end-to-end-tests.sh` installs into whatever cluster your current kubectl
context points at. Only run it against a disposable cluster.
