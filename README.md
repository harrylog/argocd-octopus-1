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
manifest under `argocd/<app>-app.yaml` pointing at that chart path. ArgoCD polls
this repo and reconciles the cluster to match.

## Apps

### pingpong

Minimal `hashicorp/http-echo` deployment + service. No secrets, no ingress -
just proving the Helm chart -> git -> ArgoCD -> cluster loop works end to end.

Deploy it:

```bash
kubectl apply -f argocd/pingpong-app.yaml
argocd app get pingpong
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

Deploy both (or let the automated ArgoCD sync pick them up on the next poll):

```bash
kubectl apply -f argocd/argo-rollouts-app.yaml
kubectl apply -f argocd/bluegreen-demo-app.yaml
```

Watch it:

```bash
kubectl -n bluegreen-demo get rollout bluegreen-demo
kubectl -n bluegreen-demo port-forward svc/bluegreen-demo-active 8081:80
curl localhost:8081/color   # -> "blue"
```

Trigger a blue/green rollout by bumping the image tag (e.g. `blue` ->
`yellow`) in `charts/bluegreen-demo/values.yaml` and pushing to `main` -
ArgoCD syncs the `Rollout` spec, which spins up new ("preview") pods on the
`yellow` image while `-active` keeps serving `blue`:

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

## Planned next steps

- Possibly an "app of apps" ArgoCD Application so `argocd/*.yaml` is itself
  managed by ArgoCD instead of `kubectl apply`d by hand.
- Canary deployments / analysis-based rollbacks with Argo Rollouts, building
  on the blue/green POC above.
