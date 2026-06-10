#!/usr/bin/env bash
# Simula rollback. Forma GitOps (default): reverte o último commit e dá push;
# ArgoCD sincroniza de volta. Use "now" p/ rollback imediato no cluster (drift).
# Uso: ./40-rollback.sh           -> git revert HEAD + push (recomendado)
#      ./40-rollback.sh now       -> kubectl rollout undo (selfHeal reverte depois)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODE="${1:-git}"
case "${MODE}" in
  git)
    need git
    cd "${ROOT}"
    git revert --no-edit HEAD
    git push
    log "commit revertido + push. ArgoCD volta pra versão anterior."
    log "acompanhe: kubectl rollout status deployment/${IMAGE} -n ${NS}"
    ;;
  now)
    need kubectl
    kubectl rollout undo deployment/${IMAGE} -n "${NS}"
    warn "drift no cluster. selfHeal do ArgoCD reverte pro estado do Git em breve."
    warn "p/ rollback permanente, use a forma git."
    ;;
  *) die "uso: $0 [git|now]" ;;
esac
