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

# K3s ships containerd; import images into it instead of using a registry.
import_to_k3s() {
  local tag="$1"
  need docker
  log "docker build ${IMAGE}:${tag}"
  docker build -t "${IMAGE}:${tag}" "${ROOT}/apps/modern-linux"
  local tar="/tmp/${IMAGE}-${tag}.tar"
  docker save "${IMAGE}:${tag}" -o "${tar}"
  log "import into k3s containerd"
  sudo k3s ctr images import "${tar}"
  rm -f "${tar}"
  sudo k3s ctr images ls | grep "${IMAGE}:${tag}" || die "image not visible in k3s"
}
