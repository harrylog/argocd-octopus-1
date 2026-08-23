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

## Planned next steps

- A small "login page" app that reads credentials from a Kubernetes Secret
  (to practice the "Managing Secrets" tutorial).
- Introduce Bitnami Sealed Secrets so the encrypted secret can actually live in
  this git repo instead of being applied out-of-band.
- Possibly an "app of apps" ArgoCD Application so `argocd/*.yaml` is itself
  managed by ArgoCD instead of `kubectl apply`d by hand.
