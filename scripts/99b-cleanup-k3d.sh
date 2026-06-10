#!/usr/bin/env bash
# Remove o cluster k3d inteiro (some com tudo: argocd, apps, namespaces).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
K3D="$(command -v k3d || echo "$HOME/bin/k3d.exe")"
[ -x "${K3D}" ] || command -v "${K3D}" >/dev/null 2>&1 || die "k3d não encontrado"
log "deletando cluster k3d ${K3D_CLUSTER}"
"${K3D}" cluster delete "${K3D_CLUSTER}"
rm -f "/tmp/k3d-${K3D_CLUSTER}.yaml"
log "removido"
