#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./docker/clean_skyscraper.sh [VERSION]
#
# This cleans local artifacts and reclaims container image space:
# - Removes docker_out/
# - If VERSION is provided, removes image localhost/scrappy-skyscraper:VERSION
# - Prunes all unused images (safe if you don't use Podman elsewhere)
# - Shows current Podman disk usage

VERSION="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Remove local build artifacts
if [ -d docker_out ]; then
  rm -rf docker_out
  echo "Removed docker_out/"
fi

# Optionally remove the specific image tag we built
if [ -n "$VERSION" ]; then
  podman rmi "localhost/scrappy-skyscraper:${VERSION}" || true
fi

# Prune all unused images (safe if you don't use Podman for other projects)
podman image prune -a -f || true

# Show current Podman disk usage
podman system df || true
