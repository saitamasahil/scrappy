#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./docker/build_skyscraper.sh [VERSION]
#
# This builds Skyscraper inside an aarch64 container and outputs a zip:
#   Result: docker_out/skyscraper_package.zip
#
# After it finishes, unzip and copy into the app:
# - Replace bin/Skyscraper.aarch64 with Skyscraper (rename as needed)
# - Copy only needed Qt/OpenSSL/ICU libs into bin/libs.aarch64/ if required
# - Do not copy generic system libs (e.g., libc, libstdc++, libX11, libGL, etc.)

VERSION="${1:-3.20.4}"

# Project root is the parent of this script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

podman build --arch=arm64 -t scrappy-skyscraper:"$VERSION" \
    --build-arg VERSION="$VERSION" \
    -f docker/Dockerfile docker

mkdir -p docker_out
podman run --rm -v "$PWD/docker_out:/output:Z" localhost/scrappy-skyscraper:"$VERSION"

echo "Created: docker_out/skyscraper_package.zip"

# Ask user before cleaning up so container image can be reused for future builds
if [ -t 0 ]; then
    read -r -p "Do you want to delete the build container image to save disk space? [y/N]: " cleanup_choice
    case "$cleanup_choice" in
        [yY][eE][sS]|[yY])
            "${SCRIPT_DIR}/clean_skyscraper.sh" "$VERSION"
            ;;
        *)
            echo "Container image 'scrappy-skyscraper:${VERSION}' kept for faster future builds."
            ;;
    esac
else
    echo "Skipping auto-cleanup in non-interactive mode. Run ./docker/clean_skyscraper.sh ${VERSION} to clean up manually."
fi
