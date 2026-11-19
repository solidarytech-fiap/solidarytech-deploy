# SolidaryTech - GitOps

Tudo o que roda no cluster EKS `solidarytech-eks`, entregue pelo **ArgoCD** (App-of-Apps) a partir da branch `main`. Código e infraestrutura AWS ficam em [`solidarytech-app`](https://github.com/solidarytech-fiap/solidarytech-app).

## Estrutura

```
k8s/
  root-app.yaml            raiz do App-of-Apps (aplicada 1x pelo argocd-install.yml)
  argocd/values.yaml       values do chart argo-cd
  apps/                    Applications: ingress-nginx, external-secrets, metrics-server,
                           kube-prometheus-stack, loki-stack, otel-collector, velero, servicos
  apps-optional/           variante Datadog do OTel Collector (ativada na semana 7)
  platform/                ClusterSecretStore (SSM Parameter Store)
  base/                    namespace, ExternalSecrets, Ingress, jobs de schema, servicos, CronJobs de backup
  overlays/prod/           tags de imagem (CI) e rightsizing (requests/limits)
  observability/           dashboards Grafana (Golden Signals, SLO, FinOps), regras de SLO e alertas
  observability-datadog/   ExternalSecret da API key do Datadog
  dr/velero/               Schedules de backup do Velero
terraform/datadog/         monitores, Watchdog, SLOs, dashboard SRE e webhook (alertas como código)
.github/workflows/         argocd-install, self-healing, datadog-terraform, dr-drill, manifests-ci
```

## Ordem de sincronização (sync waves)

| Wave | Applications |
|---|---|
| -5 | ingress-nginx, external-secrets, metrics-server |
| -4 | platform-config (ClusterSecretStore) |
| -3 | kube-prometheus-stack, loki-stack, otel-collector, velero |
| -2 | observability-config |
| -1 | velero-config |
| 0 | solidarytech (serviços) |

## Fluxo GitOps

1. Push em `solidarytech-app/src/<serviço>`: CI (testes, SAST, SCA, Trivy), imagem no ECR com tag = SHA.
2. `reusable-gitops.yml` roda `kustomize edit set image` em `k8s/overlays/prod` e faz commit em `main`.
3. O ArgoCD detecta o commit (polling de 60s) e faz o rolling update (`maxUnavailable: 0`).
4. Rollback: `git revert` do commit `deploy(<serviço>): <sha>`.

## Workflows

| Workflow | Gatilho | Função |
|---|---|---|
| Install ArgoCD + App-of-Apps | disparado pelo Terraform Apply | instala o ArgoCD e aplica a raiz |
| Self-Healing | webhook do Datadog (`repository_dispatch`) | rollout restart, verificação e linha do tempo |
| DR Drill | manual (`confirm=drill`) | backup Velero, apaga o namespace, restore, RTO medido |
| Datadog Terraform | manual | plan/apply/destroy dos monitores e SLOs |
| Manifests CI | PR/push | kustomize build, kubeconform, política de requests/limits, Trivy config |
