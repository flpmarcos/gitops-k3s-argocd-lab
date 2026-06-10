#!/usr/bin/env bash
# (Opcional) Sobe Git server LOCAL (Gitea) no cluster e cria usuário admin.
# Alternativa ao GitHub. Depois faça push via http://localhost:30300.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl

GU="${GITEA_USER:-lab}"
GP="${GITEA_PASS:-lab12345}"

log "subindo Gitea"
kubectl apply -f "${ROOT}/k8s/gitea/gitea.yaml"
kubectl rollout status deployment/gitea -n git --timeout=180s

POD="$(kubectl get pod -n git -l app=gitea -o jsonpath='{.items[0].metadata.name}')"
log "criando usuário admin '${GU}'"
kubectl exec -n git "${POD}" -- su git -c \
  "gitea admin user create --username ${GU} --password ${GP} --email ${GU}@local --admin --must-change-password=false" \
  || warn "usuário pode já existir"

log "Gitea pronto:"
log "  UI/push host : http://localhost:30300   (login ${GU}/${GP})"
log "  DNS interno  : http://gitea.git.svc.cluster.local:3000  (usado pelo ArgoCD)"
log "Crie o repo 'gitops-k3s-argocd-lab' na UI, depois:"
log "  git remote add gitea http://${GU}:${GP}@localhost:30300/${GU}/gitops-k3s-argocd-lab.git"
log "  git push gitea main"
log "E aplique:  ./scripts/20-deploy-argocd.sh gitea"
