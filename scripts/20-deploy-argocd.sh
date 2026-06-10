#!/usr/bin/env bash
# Registra as duas ArgoCD Applications (GitHub por padrão).
# Uso: ./20-deploy-argocd.sh [github|gitea]   (default: github)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl

SRC="${1:-github}"
case "${SRC}" in
  github) DIR="${ROOT}/argocd" ;;
  gitea)  DIR="${ROOT}/argocd/gitea-local" ;;
  *) die "uso: $0 [github|gitea]" ;;
esac

log "aplicando Applications de ${DIR}"
kubectl apply -f "${DIR}/app-modern-linux.yaml"
kubectl apply -f "${DIR}/app-legacy-windows.yaml"

log "applications:"
kubectl get applications -n "${ARGO_NS}"
log "ArgoCD vai sincronizar em ~3min (ou: argocd app sync app-modern-linux)"
