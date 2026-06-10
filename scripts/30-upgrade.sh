#!/usr/bin/env bash
# Simula upgrade de versão (GitOps): builda+importa a nova tag, atualiza o
# manifest no Git e dá push. ArgoCD sincroniza sozinho.
# Uso: ./30-upgrade.sh v2
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need git

TAG="${1:-}"
[ -n "${TAG}" ] || die "uso: $0 <tag>  (ex: v2)"

# 1) build + import da nova imagem
import_to_k3s "${TAG}"

# 2) bump no manifest (fonte da verdade = Git)
DEPLOY="${ROOT}/k8s/modern-linux/deployment.yaml"
sed -E -i \
  -e "s#(image: ${IMAGE}:).*#\1${TAG}#" \
  -e "s#(value: \")v[0-9]+(\")#\1${TAG}\2#" \
  "${DEPLOY}"
log "deployment.yaml -> ${IMAGE}:${TAG}"
grep -E "image: ${IMAGE}:|APP_VERSION" -A0 "${DEPLOY}" | grep -E "image:|value: \"v" || true

# 3) commit + push
cd "${ROOT}"
git add "${DEPLOY}"
git commit -m "deploy ${IMAGE} ${TAG}"
git push
log "push feito. ArgoCD vai aplicar o rolling update."
log "acompanhe: kubectl rollout status deployment/${IMAGE} -n ${NS}"
