#!/usr/bin/env bash
# Visão geral do lab.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl

echo "===== ArgoCD Applications ====="
kubectl get applications -n "${ARGO_NS}" 2>/dev/null || warn "ArgoCD não instalado"

echo; echo "===== Pods (${NS}) ====="
kubectl get pods -n "${NS}" -o wide 2>/dev/null || warn "namespace ${NS} ausente"

echo; echo "===== Services (${NS}) ====="
kubectl get svc -n "${NS}" 2>/dev/null || true

echo; echo "===== Modern Linux: /version ====="
curl -s http://localhost:30080/version 2>/dev/null && echo || warn "NodePort 30080 sem resposta (pod pronto?)"

echo; echo "===== Legacy Windows: por que Pending ====="
kubectl describe pod -n "${NS}" -l app=app-legacy-windows 2>/dev/null \
  | grep -A3 -i "events:" || warn "pod windows ainda não criado"
