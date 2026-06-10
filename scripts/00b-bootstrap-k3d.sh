#!/usr/bin/env bash
# Bootstrap via k3d (k3s dentro do Docker). RODA NO WINDOWS (git-bash) ou Linux,
# desde que o Docker esteja rodando. Sem WSL/systemd.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need docker

# --- k3d ---
if ! command -v k3d >/dev/null 2>&1; then
  warn "k3d não no PATH; baixando binário em ~/bin"
  mkdir -p "$HOME/bin"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) curl -sSL -o "$HOME/bin/k3d.exe" \
        https://github.com/k3d-io/k3d/releases/latest/download/k3d-windows-amd64.exe ;;
    *) curl -sSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash ;;
  esac
  export PATH="$HOME/bin:$PATH"
fi
K3D="$(command -v k3d || echo "$HOME/bin/k3d.exe")"

# --- cluster com NodePort 30080/30081 mapeados pro host ---
if "${K3D}" cluster list 2>/dev/null | grep -q "${K3D_CLUSTER}"; then
  log "cluster ${K3D_CLUSTER} já existe"
else
  log "criando cluster k3d ${K3D_CLUSTER}"
  "${K3D}" cluster create "${K3D_CLUSTER}" \
    -p "30080:30080@server:0" \
    -p "30081:30081@server:0"
fi

# kubeconfig isolado (evita conflito de KUBECONFIG multi-entry)
KCFG="/tmp/k3d-${K3D_CLUSTER}.yaml"
"${K3D}" kubeconfig get "${K3D_CLUSTER}" > "${KCFG}"
export KUBECONFIG="${KCFG}"
log "KUBECONFIG=${KCFG}  (exporte isto nos próximos comandos)"
kubectl get nodes

# --- ArgoCD (server-side: o CRD applicationsets estoura o limite do client-side) ---
kubectl get ns "${ARGO_NS}" >/dev/null 2>&1 || kubectl create namespace "${ARGO_NS}"
log "instalando ArgoCD (server-side apply)"
kubectl apply --server-side --force-conflicts -n "${ARGO_NS}" \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment --all -n "${ARGO_NS}"

log "senha admin ArgoCD:"
kubectl -n "${ARGO_NS}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
cat <<EOF

Próximos passos (mesma sessão, com KUBECONFIG=${KCFG}):
  ENGINE=k3d ./scripts/10-build-import.sh v1
  ./scripts/20-deploy-argocd.sh github
  ./scripts/50-status.sh
EOF
log "bootstrap k3d OK"
