#!/usr/bin/env bash
# Instala K3s + ArgoCD. Rode em Linux/WSL (NÃO no Windows git-bash).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- K3s ---
if command -v k3s >/dev/null 2>&1; then
  log "k3s já instalado"
else
  log "instalando k3s"
  curl -sfL https://get.k3s.io | sh -
fi

# kubeconfig p/ usuário atual
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"
log "kubeconfig em ~/.kube/config (export KUBECONFIG=~/.kube/config)"

need kubectl
kubectl get nodes

# --- ArgoCD ---
if kubectl get ns "${ARGO_NS}" >/dev/null 2>&1; then
  log "namespace argocd já existe"
else
  kubectl create namespace "${ARGO_NS}"
fi
log "aplicando manifests do ArgoCD"
kubectl apply -n "${ARGO_NS}" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log "aguardando ArgoCD subir (até 5min)"
kubectl wait --for=condition=available --timeout=300s deployment --all -n "${ARGO_NS}"

log "senha admin do ArgoCD:"
kubectl -n "${ARGO_NS}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
log "UI: kubectl port-forward svc/argocd-server -n ${ARGO_NS} 8443:443  ->  https://localhost:8443"
log "bootstrap OK"
