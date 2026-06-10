#!/usr/bin/env bash
# Remove o lab. Por padrão remove só as apps/namespaces; "--all" desinstala K3s.
# Uso: ./99-cleanup.sh         -> apps + namespaces gitops-lab/argocd/git
#      ./99-cleanup.sh --all   -> + k3s-uninstall.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl

kubectl delete -f "${ROOT}/argocd" --ignore-not-found 2>/dev/null || true
kubectl delete -f "${ROOT}/argocd/gitea-local" --ignore-not-found 2>/dev/null || true
kubectl delete namespace "${NS}" --ignore-not-found
kubectl delete namespace git --ignore-not-found
kubectl delete namespace "${ARGO_NS}" --ignore-not-found
log "apps e namespaces removidos"

if [ "${1:-}" = "--all" ]; then
  if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
    warn "desinstalando K3s"
    sudo /usr/local/bin/k3s-uninstall.sh
  else
    warn "k3s-uninstall.sh não encontrado"
  fi
fi
