#!/usr/bin/env bash
# Builda a imagem Linux e importa no containerd do K3s.
# Uso: ./10-build-import.sh [tag]   (default: v1)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TAG="${1:-v1}"
import_to_k3s "${TAG}"
log "imagem ${IMAGE}:${TAG} pronta no K3s"
