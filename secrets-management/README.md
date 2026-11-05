# secrets-management

Creates Kubernetes Secrets from 1Password, so secrets are never stored in this repository.

| Chart | What it does |
| --- | --- |
| [`external-secrets`](external-secrets) | External Secrets Operator: turns `ExternalSecret` resources into Kubernetes Secrets |
| [`onepassword-store`](onepassword-store) | The `onepassword` ClusterSecretStore, reading one 1Password vault |

They are separate charts because `external-secrets` installs the operator's CRDs as
templates: a ClusterSecretStore in the same Helm release would fail to install. Install
`external-secrets` first.

Upstream chart versions are pinned in each chart's `Chart.yaml`.

## external-secrets

Built from the [External Secrets Operator](https://external-secrets.io) chart. It runs three
components, one replica each: the controller, its admission webhook, and the cert-controller
that manages the webhook's certificate. Requests and limits for all three are set in
`values.yaml`.

## onepassword-store

A ClusterSecretStore using External Secrets Operator's 1Password SDK provider, which
authenticates with a 1Password service account token.

| Value | Default | Meaning |
| --- | --- | --- |
| `storeName` | `onepassword` | Name used in an ExternalSecret's `secretStoreRef` |
| `vault` | none, required | The 1Password vault the store reads. Set as a Helm parameter on the Argo CD Application, not in this repository. |
| `serviceAccountToken.secretName` | `onepassword-service-account` | Secret holding the service account token |
| `serviceAccountToken.key` | `token` | Key in that Secret |
| `serviceAccountToken.namespace` | `external-secrets` | Namespace of that Secret |

The token Secret is created by hand, once per cluster, so the token never reaches git:

```sh
read -rs OP_TOKEN && printf %s "$OP_TOKEN" | kubectl -n external-secrets create secret generic onepassword-service-account --from-file=token=/dev/stdin; unset OP_TOKEN
```

## Tests

| What | Where | Checks |
| --- | --- | --- |
| Unit tests | `onepassword-store/tests/*_test.yaml` | Store kind and name; vault is used and required; token Secret reference and overrides |
