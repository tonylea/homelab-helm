# gitops

Argo CD configuration that lives in this repository.

| Chart | What it does |
| --- | --- |
| [`argocd-clusters`](argocd-clusters) | Registers external clusters with Argo CD, so Applications can deploy to them |

## argocd-clusters

Argo CD finds the clusters it can deploy to through Secrets labelled
`argocd.argoproj.io/secret-type: cluster` in its own namespace. This chart creates one
`ExternalSecret` per entry in `clusters`. External Secrets Operator builds the cluster
Secret from 1Password, so the cluster's token never reaches git.

| Value | Meaning |
| --- | --- |
| `clusters.<name>.server` | The cluster's API server URL. `<name>` is the cluster name shown in Argo CD. |
| `clusters.<name>.onepasswordItem` | 1Password API Credentials item: the raw ServiceAccount token in `credential`, the base64-encoded CA certificate in a custom field `ca` |
| `clusters.<name>.labels` | Optional labels on the cluster Secret, for selecting clusters, for example in an ApplicationSet |
| `secretStoreRef` | Store the ExternalSecrets read from (default: ClusterSecretStore `onepassword`) |

Install it into Argo CD's namespace (`argocd`).

### Adding a cluster

Argo CD can't deploy to a cluster until it's registered, so the cluster side is set up by
hand, once:

1. Create a ServiceAccount with cluster-admin rights and a long-lived token for it. This
   matches what `argocd cluster add` creates:

   ```sh
   kubectl --context <cluster> apply -f gitops/argocd-clusters/bootstrap/argocd-manager.yaml
   ```

2. Create a 1Password **API Credentials** item, pasting each value from the clipboard so
   the token is never printed:
   - the built-in `credential` field:

     ```sh
     kubectl --context <cluster> -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' | base64 -d | pbcopy
     ```

   - a custom text field named `ca`:

     ```sh
     kubectl --context <cluster> -n kube-system get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}' | pbcopy
     ```
3. Add the cluster to the cluster's `values-<cluster>.yaml` under `clusters`.

Deleting the `argocd-manager-token` Secret on the cluster revokes the token.

### Cluster overrides

| File | Overrides |
| --- | --- |
| `values-minikube.yaml` | Registers `k3s` (`https://k3s-node-02.internal.deadrobot.co.uk:6443`, 1Password item `argocd-cluster-k3s`) with the Argo CD running on minikube |
