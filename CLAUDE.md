# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal POC repo for following Octopus Deploy's ArgoCD/GitOps certification track (Fundamentals →
Scale → Enterprise) plus assorted Codefresh Argo Rollouts tutorials, against a local k3s cluster.
The user is deliberately going deep on the whole stack (Kubernetes, Helm, ArgoCD, Argo Rollouts,
Prometheus/Grafana) — prefer explanations and changes that reinforce the underlying mechanism over
just making something work.

Full narrative docs (what each app demonstrates, how to trigger/watch each demo, bugs already
found and fixed) live in `README.md` — read it before making changes; don't duplicate it here.

## Repo convention — read before adding or touching any app

This repo is **app-of-apps**. There is exactly one Application manifest hand-applied to the
cluster, `argocd/root-app.yaml`, which points at `charts/root-app` — a Helm chart whose
`templates/applications.yaml` renders one ArgoCD `Application` per entry in its `values.yaml`
`apps` list. Every app still follows the same underlying shape as before (Helm chart at
`charts/<app>/`, `source.repoURL` pointing at **this repo** for vendored charts,
`source.path: charts/<app>`) — the difference is that shape now lives as a values-list entry
instead of a standalone YAML file.

**To add a new app**: add a Helm chart under `charts/<app>/`, then add one entry to
`charts/root-app/values.yaml`'s `apps` list (name, namespace, repoURL, path, and whichever of
`releaseName` / `valueFiles` / `parameters` / `values` the app needs) — do not hand-write a new
`argocd/<app>-app.yaml`. `argocd app sync root-app` picks up the new entry and creates the child
Application; sync that child app by name to actually deploy it.

"Everything the cluster runs is defined here in git" is the repo's explicit stated goal — this
now extends to the Application objects themselves, not just the charts they deploy. When a chart
is needed from an upstream project, vendor it (`helm pull <chart> --untar` into `charts/<app>`)
rather than pointing an entry's `repoURL` at the upstream chart repo. This was done for
`prometheus` and `charts/grafana` on 2026-08-27 after they were found sourcing straight from
upstream; the one remaining deliberate exception is `argo-rollouts`, which still sources from
`argoproj/argo-helm` upstream (same shape as `sealed-secrets`) — don't vendor it without being
asked.

`syncPolicy` on every Application — root-app and every child it renders — is manual only (no
`automated:` block). ArgoCD never auto-syncs or self-heals here. A chart/values change isn't live
until someone runs `argocd app sync <name>` (or clicks Sync in the UI); changing
`charts/root-app/values.yaml` additionally requires `argocd app sync root-app` before the child
Application it affects reflects the change.

## Environment

- Cluster: local k3s, context `default`
- ArgoCD: namespace `argocd`, UI on NodePort `30443` (https) / `30081` (http)
- Monitoring stack (`prometheus` + `grafana` Applications) lives in namespace `monitoring`
- `kubectl port-forward` sessions do not persist across terminal restarts/reboots — if a
  dashboard/service someone expects to reach at `localhost:<port>` seems "down," check whether the
  pod/Service/Application are actually healthy before assuming something broke; usually the fix is
  just restarting the port-forward, not a real regression.

## Common commands

```bash
# One-time bootstrap of a fresh cluster - creates every child Application
kubectl apply -f argocd/root-app.yaml
argocd app sync root-app

# After adding/editing an entry in charts/root-app/values.yaml
argocd app sync root-app        # re-renders the child Application object(s)
argocd app sync <app>           # then deploy the app itself

# After editing an existing app's chart (no root-app.yaml/values.yaml change needed)
argocd app sync <app>

# Validate a chart change before syncing
helm lint charts/<app>
helm template <app> charts/<app>            # add --set/-f to match the Application's helm.parameters/values
helm template root-app charts/root-app      # preview every rendered Application manifest

# ArgoCD UI admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Grafana admin password (auto-generated, not stored in git)
kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d

# Argo Rollouts CLI (promote/abort/undo) needs the kubectl plugin:
# https://argo-rollouts.readthedocs.io/en/stable/installation/#kubectl-plugin-installation
kubectl argo rollouts promote <rollout> -n <namespace>
kubectl argo rollouts undo <rollout> -n <namespace>
```

There is no build/test/lint pipeline beyond `helm lint`/`helm template` — this is a manifests-only
repo, not an application codebase.
