# argocd-octopus-1

Personal POC repo for following along Octopus Deploy's ArgoCD / GitOps tutorials.
Everything the cluster runs is defined here in git — that's the whole point of GitOps.

## Environment

- Cluster: local k3s (`kubectl config current-context` → `default`)
- ArgoCD: already installed in the `argocd` namespace, UI on NodePort `30443` (https) / `30081` (http)
- This repo: public at `https://github.com/harrylog/argocd-octopus-1`, branch `main`

## Layout

```
charts/           Helm charts for each app, one directory per app
  pingpong/        minimal HTTP echo app - the "hello world" of this POC
argocd/           ArgoCD Application manifests (one per app), applied by hand for now
```

Each app gets its own Helm chart under `charts/<app>` and its own `Application`
manifest under `argocd/<app>-app.yaml` pointing at that chart path.

Sync is manual everywhere (`syncPolicy` has no `automated:` block) - ArgoCD
never auto-syncs or self-heals. After changing a chart or pushing to `main`,
apply the change yourself:

```bash
argocd app sync <name>   # or click Sync in the UI
```

## Apps

### pingpong

Minimal `hashicorp/http-echo` deployment + service. No secrets, no ingress -
just proving the Helm chart -> git -> ArgoCD -> cluster loop works end to end.

Deploy it:

```bash
kubectl apply -f argocd/pingpong-app.yaml
argocd app sync pingpong
```

Try it:

```bash
kubectl -n pingpong port-forward svc/pingpong 8080:80
curl localhost:8080   # -> pong
```

### argo-rollouts + bluegreen-demo

Practicing Codefresh's "Blue/Green deployments with Argo Rollouts" tutorial.
Two Applications:

- `argo-rollouts` - installs the Argo Rollouts controller + CRDs from its
  upstream Helm chart (`argoproj/argo-helm`, path `charts/argo-rollouts`),
  into the `argo-rollouts` namespace. Also enables the built-in web dashboard.
- `bluegreen-demo` - a `Rollout` (drop-in replacement for a `Deployment`)
  running `argoproj/rollouts-demo`, a tiny app that renders a full-page color
  swatch matching its image tag. Two Services front it: `-active` (what real
  traffic hits) and `-preview` (where the new version lands first). Chart is
  at `charts/bluegreen-demo`.

Deploy both:

```bash
kubectl apply -f argocd/argo-rollouts-app.yaml
kubectl apply -f argocd/bluegreen-demo-app.yaml
argocd app sync argo-rollouts bluegreen-demo
```

Watch it:

```bash
kubectl -n bluegreen-demo get rollout bluegreen-demo
kubectl -n bluegreen-demo port-forward svc/bluegreen-demo-active 8081:80
curl localhost:8081/color   # -> "blue"
```

Trigger a blue/green rollout by bumping the image tag (e.g. `blue` ->
`yellow`) in `charts/bluegreen-demo/values.yaml`, pushing to `main`, then
`argocd app sync bluegreen-demo` - that updates the `Rollout` spec, which
spins up new ("preview") pods on the `yellow` image while `-active` keeps
serving `blue`:

```bash
kubectl -n bluegreen-demo port-forward svc/bluegreen-demo-preview 8082:80
curl localhost:8082/color   # -> "yellow", once the new pods are Ready
```

`autoPromotionEnabled: false` in `values.yaml` means it waits for a manual
promotion once you're happy with the preview:

```bash
kubectl argo rollouts promote bluegreen-demo -n bluegreen-demo   # flip active -> yellow
kubectl argo rollouts undo bluegreen-demo -n bluegreen-demo      # or roll back
```

(`kubectl argo rollouts` is the Rollouts CLI plugin - install via
`brew install argoproj/tap/kubectl-argo-rollouts` or see the
[install docs](https://argo-rollouts.readthedocs.io/en/stable/installation/#kubectl-plugin-installation).
Without the plugin you can still watch the rollout via `kubectl -n
bluegreen-demo get rollout bluegreen-demo -w` or the dashboard below.)

Dashboards:

- **Argo Rollouts dashboard** - visualizes the active/preview split live.
  No auth. `kubectl -n argo-rollouts port-forward svc/argo-rollouts-dashboard 3100:3100`,
  then open http://localhost:3100.
- **ArgoCD UI** - https://localhost:30443 (or whatever NodePort you've
  mapped). User `admin`, password from:
  `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

### canary-demo

Practicing Codefresh's "Canaries with Argo Rollouts" tutorial - same
controller as above (`argo-rollouts` Application), different strategy.
Where blue/green is one instant all-or-nothing cutover, canary shifts
traffic in weighted steps with pauses in between, so you can watch a small
slice of real usage hit the new version before going further.

Chart is at `charts/canary-demo`, same `argoproj/rollouts-demo` image as
`bluegreen-demo` so the two are easy to compare. `-stable` fronts the
current/majority version, `-canary` fronts the newest one - same
Service-selector-rewrite mechanism as blue/green's `-active`/`-preview`.

This cluster has no traffic-routing plugin (Istio/ALB/Traefik/...)
installed, so it's "basic" canary: Argo Rollouts approximates each
`setWeight` by scaling the canary ReplicaSet's *replica count* relative to
stable, rather than literally splitting one Service's traffic. Good enough
to see the mechanics; a real prod setup would put a mesh or ingress in
front of `-stable`/`-canary` to get exact percentages.

Deploy it:

```bash
kubectl apply -f argocd/canary-demo-app.yaml
argocd app sync argo-rollouts canary-demo   # argo-rollouts controller must exist first
```

Trigger a canary rollout the same way as blue/green - bump
`charts/canary-demo/values.yaml`'s `image.tag`, push, sync:

```bash
argocd app sync canary-demo
kubectl -n canary-demo get rollout canary-demo -w
```

`values.yaml`'s steps (`setWeight: 25 -> pause -> 50 -> pause -> 75 -> pause`)
all use indefinite pauses, so - same "control everything" philosophy as
the rest of this repo - nothing advances without an explicit promote:

```bash
kubectl argo rollouts promote canary-demo -n canary-demo   # advance one step
kubectl argo rollouts promote canary-demo -n canary-demo --full   # skip straight to 100%
kubectl argo rollouts undo canary-demo -n canary-demo      # roll back
```

Watch both the weight and the replica split live in the dashboard
(http://localhost:3100/rollouts/canary-demo) or:

```bash
kubectl -n canary-demo get rollout canary-demo
```

(See "Can canary and blue/green coexist?" below the third POC.)

### prometheus + grafana + canary-analysis-demo

Practicing Codefresh's "Automated Rollbacks with Metrics" tutorial -
canary-demo's manual `pause`/`promote` steps replaced with a Prometheus
`AnalysisTemplate` that decides continue-or-rollback on its own. This also
became the general monitoring platform for going deeper into
ArgoCD/Prometheus/Grafana beyond just Rollouts analysis.

- `prometheus` - chart: `prometheus-community/prometheus` (**not**
  `kube-prometheus-stack` - no CRDs, no bundled Alertmanager), vendored at
  `charts/prometheus`, namespace `monitoring`. kube-state-metrics and
  node-exporter enabled alongside it.
- `grafana` - chart: `grafana/grafana`, vendored at `charts/grafana`, same
  `monitoring` namespace, provisioned with the above Prometheus as its
  default datasource. Admin password auto-generated into a `grafana` Secret
  (not stored in git) - fetch it with:
  `kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d`
- `canary-analysis-demo` - chart at `charts/canary-analysis-demo`. Canary
  step lands 25% of traffic, then an inline `analysis` step (no `pause`)
  queries `kube_replicaset_status_ready_replicas` / `..._replicas` for the
  live canary ReplicaSet - Successful auto-continues to 100%, Failed
  auto-aborts and rolls back. No human in the loop on either path.

Both `prometheus` and `grafana` charts are vendored into this repo (`helm
pull ... --untar` into `charts/prometheus` / `charts/grafana`) rather than
the Application pointing at the upstream chart repo directly - keeps this
repo the single source of truth for everything the cluster runs, same as
every other app here.

Deploy (Prometheus first - the analysis step needs it up):

```bash
kubectl apply -f argocd/prometheus-app.yaml
argocd app sync argo-rollouts prometheus
kubectl apply -f argocd/grafana-app.yaml
argocd app sync grafana
kubectl apply -f argocd/canary-analysis-demo-app.yaml
argocd app sync canary-analysis-demo
```

**How the metric actually works - no app instrumentation needed.**
`argoproj/rollouts-demo` has no `/metrics` endpoint, and its container never
crashes even when its `bad-<color>` tags are misbehaving (they ship with
`ERROR_RATE` baked in, making `/color` intermittently return HTTP 500 - see
upstream `release.sh`/`main.go`). So `rollout.yaml` adds a real
`readinessProbe` against `/color`, `failureThreshold: 1` - *that's* what
turns "the app is occasionally erroring" into a Ready/NotReady signal
kube-state-metrics can see at all. Without it, Kubernetes has no idea
anything is wrong, and this whole POC silently does nothing (confirmed live
- see below).

Trigger the healthy path:

```bash
# charts/canary-analysis-demo/values.yaml: image.tag -> "purple" (or any plain color)
argocd app sync canary-analysis-demo
kubectl -n canary-analysis-demo get analysisruns -w   # -> Successful, rollout reaches 100%
```

Trigger the automatic-rollback path:

```bash
# image.tag -> "bad-red" (or any bad-<color>)
argocd app sync canary-analysis-demo
kubectl -n canary-analysis-demo get analysisruns -w   # -> Failed, rollout auto-aborts back to stable
```

Both paths are live-verified on this cluster, including two real bugs
found and fixed along the way (worth knowing if you tune the timings):

1. **`bad-*` looked identical to a healthy pod at first** - no readiness
   check existed, so `bad-red` sailed through the analysis run "Successful"
   and got auto-promoted to 100%. Fixed by adding the `readinessProbe`
   above.
2. **A genuinely healthy `blue` rollout got auto-aborted** - the analysis
   `interval` (10s) was faster than Prometheus's own `scrape_interval`
   (15s), so the first couple of measurements read stale/pre-rollout data
   as "0 ready" and burned through `failureLimit` on startup lag alone, not
   real unhealthiness. Fixed by dropping Prometheus's `scrape_interval` to
   `5s` and raising the analysis `interval` to `15s` (and yes,
   `scrape_timeout` has to shrink alongside `scrape_interval` too, or
   Prometheus rejects the reload entirely and silently keeps running on
   the old config - also confirmed live).

**Can canary and blue/green coexist?** Yes, but at different scopes:

- One `argo-rollouts` controller happily runs both strategies at once -
  that's exactly what `bluegreen-demo`, `canary-demo`, and
  `canary-analysis-demo` are doing side by side in this repo, as separate
  `Rollout` objects.
- A *single* `Rollout` cannot mix them - `spec.strategy.canary` and
  `spec.strategy.blueGreen` are mutually exclusive; you pick one per app.
  If you want blue/green's "fully inspect before any traffic" behavior
  *plus* canary's gradual ramp for the same app, canary's own `pause` /
  `AnalysisTemplate` steps (like `canary-analysis-demo` above) are Argo
  Rollouts' answer to that - not a literal combination of both strategy
  blocks.

## Planned next steps

- Possibly an "app of apps" ArgoCD Application so `argocd/*.yaml` is itself
  managed by ArgoCD instead of `kubectl apply`d by hand.
