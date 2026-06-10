#!/usr/bin/env bash
# Shared helpers for the lab scripts. Source this, don't run it.
set -euo pipefail

# Repo root = parent of scripts/
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NS="gitops-lab"
ARGO_NS="argocd"
IMAGE="app-modern-linux"

log()  { printf '\033[1;36m[lab]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

# Engine: k3s (Linux/WSL) ou k3d (Docker, roda no Windows). Default autodetect.
ENGINE="${ENGINE:-auto}"
K3D_CLUSTER="${K3D_CLUSTER:-gitops-lab}"

detect_engine() {
  [ "${ENGINE}" != "auto" ] && { echo "${ENGINE}"; return; }
  if command -v k3d >/dev/null 2>&1 && k3d cluster list 2>/dev/null | grep -q "${K3D_CLUSTER}"; then
    echo k3d
  else
    echo k3s
  fi
}

# Builda a imagem e disponibiliza pro cluster (sem registry).
#  - k3d: k3d image import (direto do Docker)
#  - k3s: docker save + k3s ctr images import
import_image() {
  local tag="$1" engine
  engine="$(detect_engine)"
  need docker
  log "docker build ${IMAGE}:${tag}"
  docker build -t "${IMAGE}:${tag}" "${ROOT}/apps/modern-linux"
  case "${engine}" in
    k3d)
      log "k3d image import (cluster ${K3D_CLUSTER})"
      k3d image import "${IMAGE}:${tag}" -c "${K3D_CLUSTER}"
      ;;
    k3s)
      local tar="/tmp/${IMAGE}-${tag}.tar"
      docker save "${IMAGE}:${tag}" -o "${tar}"
      log "import into k3s containerd"
      sudo k3s ctr images import "${tar}"
      rm -f "${tar}"
      sudo k3s ctr images ls | grep "${IMAGE}:${tag}" || die "image not visible in k3s"
      ;;
    *) die "engine desconhecido: ${engine}" ;;
  esac
}

# back-compat
import_to_k3s() { import_image "$1"; }
