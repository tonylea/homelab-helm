# homelab-helm

## Git

- Never push unless the user explicitly asks for a push in that request.
  `.claude/settings.json` makes `git push` prompt for approval; don't work around it
  with another form of the command (e.g. `git -C . push`).

## Chart conventions

- Cluster-specific settings go in `values-<cluster>.yaml`, applied on top of `values.yaml`.
- Real secrets are never in values. Charts reference Secrets by name. `ci/` values may
  contain throwaway credentials for the CI cluster.
- Upstream charts are dependencies. Pin exact versions in `Chart.yaml` and commit
  `Chart.lock`. The `charts/` folders are build output and are git-ignored.
- Bump the chart `version` on every change. CI fails a changed chart whose version
  wasn't bumped.
- Charts use `apiVersion: v2`. Chart `v3` is still experimental in Helm 4.
