# GitOps Lab — K3s + ArgoCD (Linux moderno + Windows legado)

Laboratório **local e gratuito** para simular uma esteira GitOps com Kubernetes
(**K3s**) e **ArgoCD**, cobrindo dois cenários:

| Cenário | App | Roda de verdade no K3s? |
|---|---|---|
| 1. Moderno | `.NET 8` minimal API em **Linux container** | ✅ Sim |
| 2. Legado | IIS estático em **Windows container** | ❌ Não — fica `Pending` (esperado) |

O K3s local só tem node **Linux**, então apenas o app moderno sobe. O app Windows
existe para demonstrar Dockerfile Windows + `nodeSelector: kubernetes.io/os: windows`
e o comportamento de scheduling quando **não há node Windows**.

---

## Estrutura do repositório

```
.
├── apps/
│   ├── modern-linux/            # .NET 8 API (Linux)
│   │   ├── src/                 # Program.cs, csproj, appsettings.json
│   │   ├── Dockerfile           # multi-stage Linux
│   │   └── .dockerignore
│   └── legacy-windows/          # IIS estático (Windows)
│       ├── site/index.html
│       └── Dockerfile           # base servercore/iis (só builda no Windows)
├── k8s/
│   ├── modern-linux/            # namespace, configmap, secret, deployment, service, ingress
│   └── legacy-windows/          # deployment (nodeSelector windows) + service
├── argocd/
│   ├── app-modern-linux.yaml    # ArgoCD Application
│   └── app-legacy-windows.yaml  # ArgoCD Application
└── README.md
```

---

## Automação (scripts + Makefile)

Tudo que o passo a passo faz manualmente está automatizado em `scripts/`
(rode em **Linux/WSL**). Atalhos via `make`:

```bash
make bootstrap          # instala K3s + ArgoCD
make build TAG=v1       # build + import da imagem Linux no K3s
make deploy             # registra as ArgoCD Applications (GitHub)
make status             # visão geral (apps, pods, /version, Windows Pending)
make upgrade TAG=v2     # build v2 + bump manifest + commit + push (ArgoCD sincroniza)
make rollback           # git revert + push (volta versão)
make clean              # remove apps + namespaces
make clean-all          # + desinstala K3s

# Git server local opcional (sem GitHub):
make gitea              # sobe Gitea no cluster + cria admin
make deploy-gitea       # Applications apontando pro Gitea interno
```

Sem `make`? Chame direto: `./scripts/00-bootstrap.sh`, `./scripts/10-build-import.sh v1`, etc.

> **Validado localmente:** imagem Linux builda e responde `/health`, `/version`, `/`
> (ConfigMap/Secret aplicados). Todos os manifests passam em `kubectl apply --dry-run=client`.

---

## Endpoints do app moderno

| Rota | Retorno |
|---|---|
| `/`        | greeting (ConfigMap) + version + hostname + hint do secret |
| `/health`  | `{ status: "healthy", uptimeSec }` — usado por liveness **e** readiness |
| `/version` | `{ version, framework, dotnet }` — `version` vem da env `APP_VERSION` |

---

## Documentação

| Doc | Conteúdo |
|---|---|
| [docs/AMBIENTE-DE-TESTE.md](docs/AMBIENTE-DE-TESTE.md) | O lab local (k3d + ArgoCD): topologia, comandos, **evidências** dos testes (upgrade, rollback, selfHeal, Windows `Pending`) e problemas resolvidos |
| [docs/PRODUCAO.md](docs/PRODUCAO.md) | Como montar **produção completa** com nodes Linux **+ Windows**: provisionar VMs/node pools (AKS/EKS/GKE/kubeadm), registry, secrets, GitOps HA, custos, segurança, CI/CD |

---

## Dois caminhos de execução

| Caminho | Engine | Onde roda | Quando usar |
|---|---|---|---|
| **A (recomendado)** | **k3d** (k3s em Docker) | **Windows** ou Linux, só precisa de Docker | mais rápido, sem WSL/systemd |
| B | **K3s** | Linux / WSL | quer K3s "real" no host |

Os dois usam **exatamente os mesmos manifests e o mesmo fluxo GitOps**. k3d é
literalmente k3s dentro de um container Docker — Traefik, NodePort, tudo igual.

> ✅ **Caminho A foi executado e validado de ponta a ponta**: ArgoCD sincronizando
> do GitHub, ConfigMap + Secret aplicados, NodePort respondendo, upgrade v1→v2,
> rollback v2→v1, e o app Windows em `Pending` (FailedScheduling) como esperado.

---

## Caminho A — k3d (roda no Windows, sem WSL) ⭐

### Pré-requisitos
- **Docker Desktop** rodando em modo **Linux containers** (padrão).
- `kubectl` e `git` no PATH. `k3d` é baixado automaticamente se faltar.

### Passo a passo (git-bash / WSL / Linux)

```bash
git clone https://github.com/flpmarcos/gitops-k3s-argocd-lab.git
cd gitops-k3s-argocd-lab

# 1) cluster k3d + ArgoCD (baixa o k3d se necessário)
./scripts/00b-bootstrap-k3d.sh
export KUBECONFIG=/tmp/k3d-gitops-lab.yaml   # impresso pelo script

# 2) build + import da imagem Linux (k3d image import, sem registry)
ENGINE=k3d ./scripts/10-build-import.sh v1

# 3) registrar as Applications (lê do GitHub público)
./scripts/20-deploy-argocd.sh github

# 4) status
./scripts/50-status.sh
curl http://localhost:30080/version      # {"version":"v1",...}
```

> O ArgoCD pode levar até ~3min (polling) pra sincronizar. Pra forçar agora:
> ```bash
> kubectl -n argocd annotate application app-modern-linux \
>   argocd.argoproj.io/refresh=hard --overwrite
> ```

### Bootstrap manual equivalente (sem script)

```bash
k3d cluster create gitops-lab -p "30080:30080@server:0" -p "30081:30081@server:0"
k3d kubeconfig get gitops-lab > /tmp/k3d-gitops-lab.yaml
export KUBECONFIG=/tmp/k3d-gitops-lab.yaml

docker build -t app-modern-linux:v1 apps/modern-linux
k3d image import app-modern-linux:v1 -c gitops-lab

kubectl create namespace argocd
# server-side: o CRD applicationsets é grande demais pro client-side apply
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment --all -n argocd

kubectl apply -f argocd/app-modern-linux.yaml
kubectl apply -f argocd/app-legacy-windows.yaml
```

### Limpeza (k3d)

```bash
./scripts/99b-cleanup-k3d.sh      # deleta o cluster inteiro
```

---

## Caminho B — K3s (Linux / WSL)

### Pré-requisitos

- **WSL2** (Ubuntu) no Windows, ou uma distro Linux.
- **Docker** rodando dentro do WSL/Linux (Docker Engine ou Docker Desktop com WSL integration).
- Acesso `sudo`.

> As seções 1–8 abaixo são o caminho **K3s**. Sem ferramentas pagas.

---

## 1. Instalar K3s

```bash
# Instala K3s single-node (server + agent). Traefik já vem incluso como ingress.
curl -sfL https://get.k3s.io | sh -

# K3s sobe como serviço systemd. Verifique:
sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes
```

> **WSL sem systemd?** Rode o binário direto em outro terminal:
> ```bash
> sudo k3s server --write-kubeconfig-mode=644 &
> ```

Copie o kubeconfig para seu usuário (assim o `kubectl` normal funciona sem `sudo`):

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
# Garanta que aponta para 127.0.0.1 (padrão já é)
export KUBECONFIG=~/.kube/config
```

---

## 2. Instalar kubectl

K3s já traz `k3s kubectl`. Para o `kubectl` standalone:

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

kubectl version --client
kubectl get nodes        # deve listar 1 node Ready com OS=linux
```

---

## 3. Instalar ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Aguarde os pods do ArgoCD subirem:
kubectl wait --for=condition=available --timeout=300s \
  deployment --all -n argocd
```

### Acessar a UI do ArgoCD

```bash
# Port-forward da API/UI (deixe rodando em um terminal):
kubectl port-forward svc/argocd-server -n argocd 8443:443
# UI:  https://localhost:8443   (aceite o cert self-signed)

# Senha inicial do usuário "admin":
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

(Opcional) CLI do ArgoCD:

```bash
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd && rm argocd
argocd login localhost:8443 --username admin --password <SENHA> --insecure
```

---

## 4. Buildar a imagem Linux local e importar no K3s

K3s usa o runtime **containerd**, não o Docker. Por isso, build com Docker e
**importe** a imagem para o containerd do K3s (sem precisar de registry):

```bash
cd apps/modern-linux

# Build da v1
docker build -t app-modern-linux:v1 .

# Exporta e importa no containerd do K3s
docker save app-modern-linux:v1 -o /tmp/app-modern-linux-v1.tar
sudo k3s ctr images import /tmp/app-modern-linux-v1.tar

# Confirme que o K3s enxerga a imagem
sudo k3s ctr images ls | grep app-modern-linux
```

> Os manifests usam `imagePullPolicy: IfNotPresent`, então o K3s usa a imagem
> importada e **não** tenta baixar de um registry.

---

## 5. Deploy via ArgoCD

O ArgoCD lê manifests **de um repositório Git**. Faça push deste projeto para um
Git (GitHub/GitLab gratuito) e ajuste o `repoURL` nos dois arquivos de
`argocd/` (troque `CHANGE-ME`).

```bash
# Edite argocd/app-modern-linux.yaml e argocd/app-legacy-windows.yaml:
#   repoURL: https://github.com/SEU-USUARIO/csharp-new-and-old-deploy.git

git init && git add . && git commit -m "gitops lab"
git remote add origin https://github.com/SEU-USUARIO/csharp-new-and-old-deploy.git
git push -u origin main
```

Registre as duas Applications no ArgoCD:

```bash
kubectl apply -f argocd/app-modern-linux.yaml
kubectl apply -f argocd/app-legacy-windows.yaml

# O syncPolicy é automated; o ArgoCD sincroniza sozinho. Acompanhe:
kubectl get applications -n argocd
```

### Verificar o app moderno

```bash
kubectl get pods,svc -n gitops-lab -l app=app-modern-linux

# Acesso via NodePort:
curl http://localhost:30080/health
curl http://localhost:30080/version
curl http://localhost:30080/

# Acesso via Ingress (Traefik). Adicione ao /etc/hosts:
echo "127.0.0.1 modern.local" | sudo tee -a /etc/hosts
curl http://modern.local/version
```

> **Sem Git?** Para um teste rápido 100% local, pule o ArgoCD e aplique direto:
> ```bash
> kubectl apply -f k8s/modern-linux/
> ```
> (Mas o objetivo do lab é a esteira GitOps — prefira o caminho via ArgoCD.)

---

## 5b. Alternativa ao GitHub — Git server LOCAL (Gitea no cluster)

Não quer GitHub? Rode um **Gitea dentro do próprio K3s**. Tudo offline, grátis.
Dá mais trabalho que criar repo no GitHub, mas funciona 100% local.

**Por que dentro do cluster?** Os pods do ArgoCD precisam alcançar a URL do Git.
Um git server no host (WSL `localhost`) **não é visível** pelos pods. In-cluster,
o ArgoCD usa o DNS interno `gitea.git.svc.cluster.local:3000`.

### 1. Subir o Gitea

```bash
kubectl apply -f k8s/gitea/gitea.yaml
kubectl rollout status deployment/gitea -n git
```

### 2. Criar usuário admin (one-time, via exec no pod)

```bash
POD=$(kubectl get pod -n git -l app=gitea -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n git "$POD" -- su git -c \
  "gitea admin user create --username lab --password lab12345 --email lab@local --admin --must-change-password=false"
```

### 3. Criar o repositório

UI: abra `http://localhost:30300` → login `lab` / `lab12345` → **+ New Repository**
→ nome `csharp-new-and-old-deploy` → Create.

### 4. Push deste projeto (do host/WSL via NodePort)

```bash
cd /c/Sources/sandbox/csharp-new-and-old-deploy   # ou seu path
git init && git add . && git commit -m "gitops lab"
git branch -M main
git remote add origin http://lab:lab12345@localhost:30300/lab/csharp-new-and-old-deploy.git
git push -u origin main
```

> Credencial embutida na URL só pra lab. Em uso real, use token/SSH.

### 5. Registrar as Applications (versão Gitea)

Já vêm prontas em `argocd/gitea-local/` apontando pro DNS interno:

```bash
kubectl apply -f argocd/gitea-local/app-modern-linux.yaml
kubectl apply -f argocd/gitea-local/app-legacy-windows.yaml
kubectl get applications -n argocd
```

> Se o repo Gitea for **privado**, registre a credencial no ArgoCD:
> ```bash
> argocd repo add http://gitea.git.svc.cluster.local:3000/lab/csharp-new-and-old-deploy.git \
>   --username lab --password lab12345
> ```

Daqui pra frente, **os passos 6 (upgrade) e 7 (rollback) são idênticos** —
só que `git push` vai pro Gitea local em vez do GitHub.

---

## 6. Simular atualização de versão (v1 → v2)

```bash
cd apps/modern-linux

# Build da v2 (mude a mensagem/version para ver a diferença)
docker build -t app-modern-linux:v2 .
docker save app-modern-linux:v2 -o /tmp/app-modern-linux-v2.tar
sudo k3s ctr images import /tmp/app-modern-linux-v2.tar
```

Atualize o manifest **no Git** (essa é a essência do GitOps — o Git é a fonte da verdade):

```bash
# k8s/modern-linux/deployment.yaml
#   image: app-modern-linux:v1   ->   app-modern-linux:v2
#   env APP_VERSION value: "v1"  ->   "v2"

git commit -am "deploy app-modern-linux v2"
git push
```

O ArgoCD detecta o commit e sincroniza (rolling update automático). Acompanhe:

```bash
kubectl rollout status deployment/app-modern-linux -n gitops-lab
curl http://localhost:30080/version   # version: "v2"
```

> Force a sincronização imediata, se quiser: `argocd app sync app-modern-linux`

---

## 7. Simular rollback (v2 → v1)

**Forma GitOps (recomendada)** — reverta o commit:

```bash
git revert --no-edit HEAD   # desfaz o commit do v2
git push
# ArgoCD sincroniza de volta para v1
kubectl rollout status deployment/app-modern-linux -n gitops-lab
curl http://localhost:30080/version   # version: "v1"
```

**Forma ArgoCD (UI/CLI)** — histórico de sync:

```bash
argocd app history app-modern-linux
argocd app rollback app-modern-linux <ID-da-revisão-anterior>
```

**Forma Kubernetes nativa** (drift — o selfHeal do ArgoCD reverte depois):

```bash
kubectl rollout undo deployment/app-modern-linux -n gitops-lab
```

---

## 8. Por que o app Windows NÃO sobe no K3s local

O Deployment `app-legacy-windows` tem:

```yaml
nodeSelector:
  kubernetes.io/os: windows
```

O scheduler do Kubernetes só coloca o Pod num node cujo label
`kubernetes.io/os=windows` bata. O K3s local é **single-node Linux**
(`kubernetes.io/os=linux`), então **nenhum node satisfaz o seletor**.

Resultado esperado:

```bash
kubectl apply -f k8s/legacy-windows/      # ou via ArgoCD
kubectl get pods -n gitops-lab -l app=app-legacy-windows
# NAME                                   READY   STATUS    RESTARTS   AGE
# app-legacy-windows-xxxxxxxxxx-xxxxx     0/1     Pending   0          30s

kubectl describe pod -n gitops-lab -l app=app-legacy-windows | tail -n 15
# Events:
#   Warning  FailedScheduling  ...  0/1 nodes are available:
#   1 node(s) didn't match Pod's node affinity/selector.
```

No **ArgoCD**, a Application aparece como **Synced** (os manifests foram
aplicados corretamente) mas **Health = Progressing/Missing**, porque o Pod
nunca fica `Running`. Isso é **correto e intencional**.

### Como subiria de verdade

1. Adicionar um **node Windows Server** ao cluster (`kubernetes.io/os=windows`)
   — exige um cluster que suporte Windows nodes (não o K3s single-node Linux).
2. Buildar a imagem Windows **em um host Windows** com Windows containers:
   ```powershell
   cd apps\legacy-windows
   docker build -t app-legacy-windows:423 .
   ```
   (Não builda em Linux/WSL — a base `servercore/iis` é Windows-only.)
3. Publicar a imagem num registry acessível pelo node Windows.

Por isso, no lab local, o cenário Windows é **simulação documentada**: o
Dockerfile e os manifests estão prontos e corretos, mas o ambiente K3s Linux
não tem onde executá-los.

---

## Versionamento de imagens (exemplos)

| App | Tags de exemplo | Convenção |
|---|---|---|
| Moderno (Linux) | `app-modern-linux:v1`, `app-modern-linux:v2` | semântico simples |
| Legado (Windows) | `app-legacy-windows:423`, `app-legacy-windows:455` | número de build |

```bash
# Linux
docker build -t app-modern-linux:v1 apps/modern-linux
docker build -t app-modern-linux:v2 apps/modern-linux

# Windows (só num host Windows)
docker build -t app-legacy-windows:423 apps/legacy-windows
docker build -t app-legacy-windows:455 apps/legacy-windows
```

A "promoção" de versão acontece **trocando a tag no manifest do Git** e deixando
o ArgoCD sincronizar — nunca com `kubectl edit` direto no cluster.

---

## Limpeza

```bash
kubectl delete -f argocd/ --ignore-not-found
kubectl delete namespace gitops-lab --ignore-not-found
kubectl delete namespace argocd --ignore-not-found

# Desinstalar K3s por completo:
/usr/local/bin/k3s-uninstall.sh
```

---

## Troubleshooting (perrengues reais já resolvidos)

| Sintoma | Causa | Fix (já aplicado no repo) |
|---|---|---|
| `CreateContainerConfigError` + `image has non-numeric user (app)` | `runAsNonRoot: true` com a imagem .NET 8 que usa user **nome** `app`, não UID | `runAsUser: 1654` no `securityContext` |
| `CustomResourceDefinition "applicationsets.argoproj.io" is invalid: metadata.annotations: Too long` | install do ArgoCD via `kubectl apply` client-side estoura o limite de 256KB de annotation | `kubectl apply --server-side --force-conflicts` |
| App moderno fica `ImagePullBackOff` | imagem não foi importada pro cluster | `ENGINE=k3d ./scripts/10-build-import.sh v1` (ou `k3s ctr images import`) |
| ArgoCD não pega o commit na hora | reconciliação é polling (~3min) | `kubectl -n argocd annotate application <app> argocd.argoproj.io/refresh=hard --overwrite` |
| App Windows `Pending` | **esperado** — sem node `kubernetes.io/os=windows` | nada a fazer; é o objetivo do cenário 2 |

---

## Resumo do fluxo GitOps

```
Dev edita manifest  ->  git push  ->  ArgoCD detecta  ->  sync no K3s
        ^                                                      |
        |-------------- rollback = git revert -----------------|
```

- **Git é a fonte da verdade.** Mudanças no cluster que divergem do Git são
  revertidas pelo `selfHeal`.
- **App moderno Linux**: ciclo completo (deploy, upgrade, rollback) funcionando.
- **App legado Windows**: pronto e correto, mas `Pending` por falta de node
  Windows — exatamente o que o lab quer demonstrar.
