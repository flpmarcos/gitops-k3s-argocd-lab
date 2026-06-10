# Ambiente de Teste — GitOps Lab (k3d + ArgoCD)

Registro do laboratório local executado e validado de ponta a ponta. Serve como
referência do que o ambiente de teste faz, como foi montado e quais evidências
comprovam o funcionamento.

> Para o passo a passo de execução, ver o [README](../README.md).
> Para montar o equivalente em produção, ver [PRODUCAO.md](./PRODUCAO.md).

---

## 1. Objetivo do ambiente de teste

Simular uma esteira GitOps com Kubernetes cobrindo **dois cenários**:

| Cenário | Aplicação | Container | Resultado esperado no lab |
|---|---|---|---|
| 1 — Moderno | .NET 8 minimal API | Linux | Roda de verdade (Running/Healthy) |
| 2 — Legado | IIS estático | Windows | Fica `Pending` (sem node Windows) — **intencional** |

O ambiente de teste **não** tem node Windows. O cenário 2 existe para validar o
Dockerfile Windows, os manifests e o comportamento do scheduler — não para
executar o container Windows.

---

## 2. Stack do ambiente de teste

| Componente | Tecnologia | Observação |
|---|---|---|
| Cluster | **k3d** (k3s dentro de Docker) | roda no Windows, sem WSL/systemd |
| GitOps | **ArgoCD** | reconciliação automática a partir do Git |
| Repositório Git | GitHub público | fonte da verdade dos manifests |
| App moderna | .NET 8 (`/`, `/health`, `/version`) | imagem `app-modern-linux:v1/v2` |
| App legada | IIS (página estática) | imagem `app-legacy-windows:423/455` |
| Ingress | Traefik (default do k3s) | NodePort 30080/30081 mapeados pro host |
| Registry | nenhum | imagem importada via `k3d image import` |

### Por que k3d e não K3s direto

- Roda no **Windows** com o Docker Desktop existente — sem WSL, sem systemd.
- É **k3s de verdade** dentro de container: Traefik, NodePort, comportamento idêntico.
- Carregar imagem é trivial: `k3d image import` (sem `docker save` + `k3s ctr`).

---

## 3. Topologia

```
┌─────────────────────────── Host Windows (Docker Desktop) ───────────────────────────┐
│                                                                                       │
│   Browser ──► https://localhost:8443 (port-forward) ──► ArgoCD UI                     │
│   curl    ──► http://localhost:30080 ─────────────────► Service NodePort              │
│                                                                                       │
│   ┌───────────────── Cluster k3d "gitops-lab" (1 node Linux) ─────────────────────┐  │
│   │                                                                                │  │
│   │   namespace argocd        namespace gitops-lab                                 │  │
│   │   ┌─────────────┐         ┌──────────────────────────────────────────────┐    │  │
│   │   │  ArgoCD     │ ─watch─►│  app-modern-linux  (Deployment 2x) RUNNING ✅ │    │  │
│   │   │  (controller│  GitHub │  ConfigMap + Secret + Service NodePort 30080  │    │  │
│   │   │   + repo)   │         │                                              │    │  │
│   │   └─────────────┘         │  app-legacy-windows (Deployment 1x) PENDING 🔴│    │  │
│   │         │                 │  nodeSelector os=windows → sem node → Pending │    │  │
│   │         │                 └──────────────────────────────────────────────┘    │  │
│   └─────────┼────────────────────────────────────────────────────────────────────┘  │
└─────────────┼────────────────────────────────────────────────────────────────────────┘
              │
              ▼
   GitHub: flpmarcos/gitops-k3s-argocd-lab  (manifests = fonte da verdade)
```

---

## 4. Como foi montado (comandos reais)

```bash
# 1) cluster k3d com NodePort mapeados pro host
k3d cluster create gitops-lab -p "30080:30080@server:0" -p "30081:30081@server:0"
k3d kubeconfig get gitops-lab > ~/.kube/k3d-gitops-lab.yaml
export KUBECONFIG=~/.kube/k3d-gitops-lab.yaml

# 2) imagem Linux buildada e importada (sem registry)
docker build -t app-modern-linux:v1 apps/modern-linux
k3d image import app-modern-linux:v1 -c gitops-lab

# 3) ArgoCD (server-side por causa do CRD applicationsets, grande demais p/ client-side)
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment --all -n argocd

# 4) Applications (ArgoCD passa a observar o GitHub)
kubectl apply -f argocd/app-modern-linux.yaml
kubectl apply -f argocd/app-legacy-windows.yaml
```

---

## 5. Evidências coletadas

### 5.1 Estado das aplicações

```
$ kubectl get applications -n argocd
NAME                 SYNC STATUS   HEALTH STATUS
app-legacy-windows   Synced        Degraded     # manifest aplicado, mas Pod Pending
app-modern-linux     Synced        Healthy

$ kubectl get pods -n gitops-lab
NAME                                  READY   STATUS    RESTARTS   AGE
app-legacy-windows-5547944697-xdhbg   0/1     Pending   0          18m   # 🔴 Windows
app-modern-linux-699c58f594-q9pf4     1/1     Running   0          12m   # 🟢 Linux
app-modern-linux-699c58f594-w2nkg     1/1     Running   0          13m   # 🟢 Linux
```

### 5.2 Por que o Windows não roda

```
$ kubectl get events -n gitops-lab --field-selector reason=FailedScheduling
FailedScheduling  pod/app-legacy-windows-...  0/1 nodes are available:
                  1 node(s) didn't match Pod's node affinity/selector.

$ kubectl get deployment app-legacy-windows -n gitops-lab \
    -o jsonpath='{.spec.template.spec.nodeSelector}'
{"kubernetes.io/os":"windows"}

$ kubectl get nodes -o jsonpath='{.items[0].metadata.labels.kubernetes\.io/os}'
linux
```

Conclusão: o Pod exige um node `kubernetes.io/os=windows`; o único node é `linux`;
o scheduler não tem onde colocar → `Pending` permanente. Esperado e correto.

### 5.3 Endpoints da app moderna

```
$ curl http://localhost:30080/health
{"status":"healthy","uptimeSec":22}

$ curl http://localhost:30080/version
{"version":"v1","framework":"1.0.0","dotnet":"8.0.28"}

$ curl http://localhost:30080/
{"message":"Hello from modern Linux app (via ConfigMap)",   # ConfigMap aplicado
 "version":"v1","secretHint":"de****ue",                     # Secret aplicado (mascarado)
 "hostname":"app-modern-linux-699c58f594-w2nkg"}
```

### 5.4 Upgrade v1 → v2 (GitOps)

```
# edita o manifest, commita e dá push (Git = fonte da verdade)
$ sed -E -i 's#(image: app-modern-linux:).*#\1v2#; s#(value: ")v[0-9]+(")#\1v2\2#' \
    k8s/modern-linux/deployment.yaml
$ git commit -am "deploy app-modern-linux v2" && git push

# ArgoCD detecta e faz rolling update
$ kubectl rollout status deployment/app-modern-linux -n gitops-lab
deployment "app-modern-linux" successfully rolled out

$ curl http://localhost:30080/version
{"version":"v2",...}                       # ✅ nova versão no ar
```

### 5.5 Rollback v2 → v1 (git revert)

```
$ git revert HEAD && git push
$ # ArgoCD reaplica
$ curl http://localhost:30080/version
{"version":"v1",...}                        # ✅ versão anterior restaurada
```

### 5.6 selfHeal (drift revertido automaticamente)

```
$ kubectl scale deployment/app-modern-linux -n gitops-lab --replicas=5
deployment.apps/app-modern-linux scaled
$ kubectl get deployment app-modern-linux -n gitops-lab -o jsonpath='{.spec.replicas}'
2     # ArgoCD reverteu para 2 (valor do Git) em segundos
```

---

## 6. Problemas reais encontrados e correções

| Sintoma | Causa | Correção |
|---|---|---|
| `CreateContainerConfigError` + `image has non-numeric user (app)` | `runAsNonRoot: true` com imagem .NET 8 que usa user **nome** `app` | `runAsUser: 1654` no `securityContext` |
| CRD `applicationsets.argoproj.io` `metadata.annotations: Too long` | `kubectl apply` client-side estoura limite de 256 KB | `kubectl apply --server-side --force-conflicts` |
| `kubectl` caindo em cluster errado | `KUBECONFIG` global apontando p/ múltiplos clusters (incl. um remoto) | kubeconfig isolado: `export KUBECONFIG=~/.kube/k3d-gitops-lab.yaml` |

---

## 7. Limitações do ambiente de teste

- **Sem node Windows** → cenário 2 nunca roda (por design).
- **Single-node**, sem HA, sem PV real persistente além do local-path.
- **Sem registry** → imagens importadas manualmente; não há `docker push`.
- **Sem TLS real** no ingress, sem DNS, sem observabilidade.
- ArgoCD com senha inicial e sem SSO.

Tudo isso é resolvido no ambiente de produção — ver [PRODUCAO.md](./PRODUCAO.md).
