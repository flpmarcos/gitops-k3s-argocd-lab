# Ambiente de Produção — GitOps com nodes Linux + Windows

Guia para levar o cenário do laboratório a um ambiente de produção **real**, onde
**as duas aplicações rodam de verdade**: a moderna (.NET 8 / Linux) e a legada
(IIS / Windows). Cobre arquitetura, provisionamento de infraestrutura ("contratar"
as VMs / node pools), custos, registry, GitOps em produção, segurança e CI/CD.

> Ambiente de teste correspondente: [AMBIENTE-DE-TESTE.md](./AMBIENTE-DE-TESTE.md).

---

## 1. A diferença essencial em relação ao lab

No lab, o app Windows fica `Pending` porque **não existe node Windows**. Em
produção, o cluster precisa de **dois tipos de worker node**:

| Node pool | OS | Roda |
|---|---|---|
| Linux | Linux | app moderna (.NET 8), ArgoCD, ingress, observabilidade |
| Windows | Windows Server 2022 | app legada (IIS / .NET Framework) |

Kubernetes suporta clusters **mistos**: o control-plane é sempre Linux; os workers
podem ser Linux **e** Windows ao mesmo tempo. O `nodeSelector: kubernetes.io/os: windows`
(que no lab causava `Pending`) passa a encontrar node e o Pod sobe.

---

## 2. Onde rodar — opções de plataforma

| Plataforma | Suporte Windows node | Esforço | Quando escolher |
|---|---|---|---|
| **Azure AKS** ⭐ | Nativo (Windows node pool) | Baixo | Melhor suporte a Windows containers; recomendado |
| AWS EKS | Sim (Windows managed node group) | Médio | Já é casa AWS |
| Google GKE | Sim (Windows node pool) | Médio | Já é casa GCP |
| On-prem / IaaS (kubeadm) | Sim (manual) | Alto | Sem nuvem; data center próprio |

> **Recomendação:** **AKS**. A Microsoft mantém as imagens base Windows e o
> suporte a Windows containers em Kubernetes é mais maduro lá.

---

## 3. Arquitetura de produção (alvo)

```
                          ┌──────────────────────────────────────┐
                          │            Git (repo único)           │
                          │  manifests + ArgoCD Applications      │
                          └───────────────┬──────────────────────┘
                                          │ watch (GitOps)
                  ┌───────────────────────▼───────────────────────────────┐
                  │                  Cluster Kubernetes                    │
                  │                (control-plane gerenciado)             │
                  │                                                        │
                  │   ArgoCD (HA)        Ingress (NGINX/Traefik) + TLS     │
                  │       │                        │                       │
                  │   ┌───▼─────────── Linux node pool ───────────────┐    │
                  │   │  app-modern-linux (.NET 8)  +  add-ons         │    │
                  │   └────────────────────────────────────────────────┘   │
                  │   ┌──────────────── Windows node pool ────────────┐    │
                  │   │  app-legacy-windows (IIS / .NET Framework)     │    │
                  │   └────────────────────────────────────────────────┘   │
                  └────────────────────────┬───────────────────────────────┘
                                           │ pull
                          ┌────────────────▼─────────────────┐
                          │   Container Registry (ACR/ECR)    │
                          │  app-modern-linux:vN              │
                          │  app-legacy-windows:NNN           │
                          └──────────────────────────────────┘
```

Componentes de produção que **não** existem no lab:
- Registry gerenciado (ACR/ECR/GHCR) com `docker push`.
- Ingress com **TLS** (cert-manager + Let's Encrypt) e DNS.
- Secrets seguros (Sealed Secrets / SOPS / Key Vault), não `stringData` no Git.
- Observabilidade (Prometheus, Grafana, Loki) e alertas.
- ArgoCD em HA + SSO/RBAC.
- CI que builda/escaneia/assina imagens e atualiza tags por GitOps.

---

## 4. Provisionar a infraestrutura — "contratar" as VMs/nodes

### 4.1 Azure AKS (recomendado) — passo a passo

Pré-requisitos: conta Azure, `az` CLI. Há **crédito grátis** para começar; depois
é pago por uso (ver custos na seção 9).

```bash
# 0) login e variáveis
az login
RG=rg-gitops-prod
LOC=brazilsouth
AKS=aks-gitops-prod
ACR=acrgitopsprod$RANDOM     # nome global único

# 1) grupo de recursos
az group create -n $RG -l $LOC

# 2) registry de container (ACR)
az acr create -g $RG -n $ACR --sku Standard

# 3) cluster AKS — começa com node pool LINUX (system)
az aks create \
  -g $RG -n $AKS \
  --location $LOC \
  --node-count 2 \
  --node-vm-size Standard_D2s_v5 \
  --network-plugin azure \
  --attach-acr $ACR \
  --generate-ssh-keys \
  --windows-admin-username azureuser \
  --windows-admin-password '<SENHA-FORTE-AQUI>'    # exigido p/ habilitar Windows depois

# 4) adicionar o node pool WINDOWS (é aqui que "contrata" as VMs Windows)
az aks nodepool add \
  -g $RG --cluster-name $AKS \
  --os-type Windows \
  --name win22 \
  --node-count 1 \
  --node-vm-size Standard_D2s_v5 \
  --os-sku Windows2022

# 5) credenciais do kubectl
az aks get-credentials -g $RG -n $AKS

# 6) conferir os dois tipos de node
kubectl get nodes -L kubernetes.io/os
# NAME                   OS-...   kubernetes.io/os
# aks-nodepool1-...      Ready    linux
# akswin22-...           Ready    windows   ◄── agora existe node Windows!
```

A partir daqui, o Pod `app-legacy-windows` **sai de `Pending` e roda**, porque o
`nodeSelector: kubernetes.io/os: windows` encontra o pool `win22`.

> **Importante (Windows pools):** o Kubernetes adiciona automaticamente o taint
> `node.kubernetes.io/os` em alguns setups; e é boa prática **taintar** o pool
> Windows para impedir que workloads Linux caiam nele. Ver seção 6.

### 4.2 AWS EKS — resumo

```bash
# cluster com eksctl (control-plane + node group Linux)
eksctl create cluster --name gitops-prod --region us-east-1 \
  --nodegroup-name linux --node-type t3.large --nodes 2

# habilitar suporte a Windows e adicionar node group Windows
eksctl utils install-vpc-controllers --cluster gitops-prod --approve
eksctl create nodegroup --cluster gitops-prod \
  --name windows --node-ami-family WindowsServer2022FullContainer \
  --node-type t3.large --nodes 1
```
Registry: **ECR**. Login: `aws ecr get-login-password | docker login ...`.

### 4.3 GCP GKE — resumo

```bash
gcloud container clusters create gitops-prod --num-nodes=2 \
  --machine-type=e2-standard-2 --release-channel=regular
# node pool Windows
gcloud container node-pools create windows \
  --cluster=gitops-prod --image-type=WINDOWS_LTSC_CONTAINERD \
  --machine-type=e2-standard-2 --num-nodes=1
```
Registry: **Artifact Registry**.

### 4.4 On-prem / IaaS sem nuvem gerenciada (kubeadm) — quando não pode pagar nuvem

Para rodar **com VMs próprias** (Hyper-V, VMware, ou IaaS "cru"):

1. **Control-plane Linux** (1+ VM Ubuntu): `kubeadm init`.
2. **CNI com suporte a Windows**: Calico ou Flannel (host-gw). CNIs comuns
   **não** suportam Windows — escolher um que suporte é crítico.
3. **VM(s) Windows Server 2022** com a feature *Containers* e containerd:
   - ISO **Evaluation grátis** (180 dias) para teste; licença Windows Server
     paga para uso real e contínuo.
   - Instalar containerd + kubelet (script oficial `PrepareNode.ps1` da Microsoft).
4. **Join** do node Windows: `kubeadm join ...` (gerado pelo control-plane).
5. Validar: `kubectl get nodes -L kubernetes.io/os` mostra node `windows`.

Custos de VM aqui = custo das máquinas/host (energia + hardware on-prem, ou
preço/hora do provedor IaaS). Em IaaS, "contratar a VM" é criar uma instância
Windows Server (ex.: Azure VM, EC2 Windows, Compute Engine Windows) e juntá-la
ao cluster manualmente.

---

## 5. Imagens em produção (registry + build Windows)

### 5.1 Linux (.NET 8) — qualquer runner Linux

```bash
docker build -t $ACR.azurecr.io/app-modern-linux:v1 apps/modern-linux
az acr login -n $ACR              # ou docker login
docker push $ACR.azurecr.io/app-modern-linux:v1
```

### 5.2 Windows (IIS / .NET Framework) — **exige host Windows**

A imagem base `mcr.microsoft.com/windows/servercore/iis` (ou
`dotnet/framework/aspnet:4.8`) **só builda em Windows com Windows containers**.
Em CI, use um **runner Windows**:

```yaml
# GitHub Actions — job em runner Windows
build-windows:
  runs-on: windows-2022
  steps:
    - uses: actions/checkout@v4
    - run: docker build -t $env:ACR/app-legacy-windows:423 apps/legacy-windows
    - run: docker push $env:ACR/app-legacy-windows:423
```

> **Versão da base importa:** a versão do Windows Server da **imagem base** deve
> ser compatível com a do **node Windows** (host). `ltsc2022` na imagem ⇄ node
> Windows Server 2022. Incompatibilidade = container não inicia.

### 5.3 Manifests em produção

Trocar `imagePullPolicy: IfNotPresent` (lab) por imagens do registry:

```yaml
# k8s/modern-linux/deployment.yaml (prod)
image: acrgitopsprod.azurecr.io/app-modern-linux:v1
imagePullPolicy: IfNotPresent   # com tag imutável; nunca :latest em prod
```

E remover do Git o `Secret` em texto (lab). Ver seção 7.

---

## 6. Agendamento Windows vs Linux (taints/tolerations)

Para garantir que cada workload caia no node certo:

```yaml
# app-legacy-windows (prod): seletor + toleration do taint do pool Windows
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/os: windows
      tolerations:
        - key: "os"
          operator: "Equal"
          value: "windows"
          effect: "NoSchedule"
```

Aplicar o taint no pool Windows (ex. AKS já permite via `--node-taints os=windows:NoSchedule`
no `nodepool add`). Assim, **só** Pods que toleram caem no Windows; o resto fica no Linux.

A app moderna mantém `nodeSelector: kubernetes.io/os: linux` (já está no manifest).

---

## 7. Secrets em produção (NÃO usar o do lab)

O lab usa `Secret` com `stringData` versionado no Git — **proibido em produção**.
Opções:

| Solução | Como funciona |
|---|---|
| **Sealed Secrets** (Bitnami) | criptografa o Secret; só o controller no cluster descriptografa; pode versionar no Git |
| **SOPS + age/KMS** | criptografa valores no arquivo; ArgoCD descriptografa no sync |
| **External Secrets Operator** | lê de Azure Key Vault / AWS Secrets Manager / Vault e cria o Secret no cluster |

Fluxo recomendado em AKS: **Azure Key Vault + External Secrets** (ou CSI driver).
O Git guarda só a *referência*, nunca o valor.

---

## 8. GitOps em produção (ArgoCD)

- **ArgoCD em HA** (`install-ha.yaml`), atrás de Ingress + TLS + SSO (OIDC).
- **Estrutura de repos**: separar config (`gitops-config`) do código da app; usar
  *App of Apps* ou **ApplicationSet** para gerenciar múltiplos ambientes
  (dev/stg/prod) e múltiplos apps.
- **Promoção de versão sem editar YAML na mão**: **ArgoCD Image Updater** observa o
  registry e abre commit bumpando a tag — mantendo o Git como fonte da verdade.
- **Sync policy**: `automated` com `prune` + `selfHeal` (como no lab), mais
  *sync windows* e *health checks* por app.
- **Rollback**: `argocd app rollback` ou `git revert` (igual ao lab, validado).

Exemplo de ApplicationSet (um app por ambiente):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: { name: app-modern-linux, namespace: argocd }
spec:
  generators:
    - list:
        elements:
          - { env: stg, ns: gitops-stg }
          - { env: prod, ns: gitops-prod }
  template:
    metadata: { name: 'app-modern-linux-{{env}}' }
    spec:
      project: default
      source:
        repoURL: https://github.com/flpmarcos/gitops-k3s-argocd-lab.git
        targetRevision: main
        path: 'k8s/overlays/{{env}}/modern-linux'   # kustomize por ambiente
      destination: { server: https://kubernetes.default.svc, namespace: '{{ns}}' }
      syncPolicy: { automated: { prune: true, selfHeal: true } }
```

---

## 9. Custos (ordem de grandeza)

> Valores **aproximados**, variam por região/câmbio/SKU. Sempre confirmar no
> calculadora do provedor. Windows custa **mais** que Linux (licença do SO embutida).

| Item | Exemplo | Custo aproximado |
|---|---|---|
| Control-plane AKS | gerenciado | grátis (paga só os nodes) — EKS/GKE cobram ~US$0,10/h |
| Node Linux | `Standard_D2s_v5` (2 vCPU/8GB) | ~US$70–100/mês por VM |
| Node Windows | `Standard_D2s_v5` Windows | ~US$130–180/mês por VM (licença Windows embutida) |
| Registry | ACR Standard | ~US$20/mês |
| Tráfego/LB/IP | Load Balancer + egress | ~US$20–40/mês |

**Dicas de custo:**
- Windows node é o item mais caro → manter **1 node Windows pequeno** só para a app legada.
- Usar **autoscaling** (cluster autoscaler) e escalar Windows para 0 fora de uso, se possível.
- **Spot/low-priority** nodes para cargas tolerantes a interrupção.
- Aproveitar **crédito grátis** inicial (Azure/AWS/GCP) para validar antes de comprometer.

---

## 10. Observabilidade e operação

- **Métricas**: Prometheus + Grafana (kube-prometheus-stack). Windows: usar
  `windows-exporter` como DaemonSet no pool Windows.
- **Logs**: Loki/Promtail ou solução gerenciada (Azure Monitor / CloudWatch).
- **Probes**: as `readinessProbe`/`livenessProbe` do lab continuam válidas; para
  o IIS, expor um endpoint simples e apontar a probe HTTP nele.
- **Ingress + TLS**: NGINX Ingress ou Traefik + cert-manager (Let's Encrypt).
- **DNS**: registro A/CNAME apontando para o IP do Load Balancer/Ingress.

---

## 11. Segurança (hardening de produção)

- Imagens com **tag imutável** (nunca `:latest`); **scan** (Trivy/Grype) no CI.
- **Assinatura** de imagem (cosign) e *admission* (Kyverno/Gatekeeper).
- `securityContext` restritivo (já aplicado na app Linux: `runAsNonRoot`,
  `runAsUser: 1654`, `readOnlyRootFilesystem`, `drop ALL`).
- **NetworkPolicies** entre namespaces.
- **RBAC** mínimo; ArgoCD com SSO e projetos isolados.
- Secrets fora do Git (seção 7); rotação periódica.
- Patching de nodes (Linux e **Windows** — atenção a janelas de manutenção do SO).

---

## 12. CI/CD recomendado

```
push no código
   ├─ Linux:   runner Linux  → build → scan → push ACR (app-modern-linux:vN)
   └─ Windows: runner Windows → build → push ACR (app-legacy-windows:NNN)
        │
        ▼
ArgoCD Image Updater detecta nova tag → commit no repo de config (bump da tag)
        │
        ▼
ArgoCD sincroniza → rolling update no cluster (Linux e/ou Windows)
        │
        ▼
rollback = git revert (ou argocd app rollback)   ← mesmo fluxo validado no lab
```

---

## 13. Checklist de prontidão para produção

- [ ] Cluster gerenciado com node pools **Linux + Windows** (`kubectl get nodes -L kubernetes.io/os`)
- [ ] Registry com imagens versionadas e scan habilitado
- [ ] Build Windows em runner Windows (base ⇄ versão do node)
- [ ] Taints/tolerations separando workloads Windows/Linux
- [ ] Secrets fora do Git (Key Vault / Sealed Secrets / SOPS)
- [ ] Ingress + TLS + DNS
- [ ] ArgoCD HA + SSO + ApplicationSet por ambiente
- [ ] Observabilidade (métricas/logs/alertas), incl. `windows-exporter`
- [ ] Políticas de segurança (NetworkPolicy, RBAC, admission, assinatura)
- [ ] Estratégia de custo (tamanho/quantidade de nodes Windows, autoscaling, spot)
- [ ] Runbook de rollback testado (git revert / argocd rollback)
