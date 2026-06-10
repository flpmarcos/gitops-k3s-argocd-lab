# Atalhos do lab. Rode em Linux/WSL. (Windows: use os scripts em ./scripts direto.)
.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

.PHONY: help bootstrap bootstrap-k3d gitea build build-k3d deploy deploy-gitea upgrade rollback rollback-now status clean clean-all clean-k3d

help: ## Lista os alvos
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

bootstrap: ## [WSL] Instala K3s + ArgoCD
	./scripts/00-bootstrap.sh

bootstrap-k3d: ## [Windows/Docker] Cria cluster k3d + ArgoCD
	./scripts/00b-bootstrap-k3d.sh

gitea: ## (Opcional) Git server local no cluster
	./scripts/05-gitea.sh

build: ## Build+import imagem Linux (TAG=v1)
	./scripts/10-build-import.sh $(or $(TAG),v1)

build-k3d: ## Build+import via k3d (TAG=v1)
	ENGINE=k3d ./scripts/10-build-import.sh $(or $(TAG),v1)

deploy: ## Registra ArgoCD Apps (GitHub)
	./scripts/20-deploy-argocd.sh github

deploy-gitea: ## Registra ArgoCD Apps (Gitea local)
	./scripts/20-deploy-argocd.sh gitea

upgrade: ## Upgrade de versão (TAG=v2)
	./scripts/30-upgrade.sh $(or $(TAG),v2)

rollback: ## Rollback via git revert
	./scripts/40-rollback.sh git

rollback-now: ## Rollback imediato (drift)
	./scripts/40-rollback.sh now

status: ## Visão geral do lab
	./scripts/50-status.sh

clean: ## Remove apps + namespaces
	./scripts/99-cleanup.sh

clean-all: ## Remove tudo + desinstala K3s
	./scripts/99-cleanup.sh --all

clean-k3d: ## Deleta o cluster k3d inteiro
	./scripts/99b-cleanup-k3d.sh
