#!/bin/bash

set -euo pipefail

# Variables (newer muOS)
REPO_URL="https://api.github.com/repos/saitamasahil/scrappy/releases/latest"
TARGET_DIR="$MUOS_STORE_DIR/application"
TEMP_DIR=$(mktemp -d)

# Ensure MUOS_STORE_DIR is set
if [ -z "${MUOS_STORE_DIR:-}" ]; then
  echo "Error: MUOS_STORE_DIR is not set in the environment." >&2
  exit 1
fi

# Fetch the latest release information
echo "Fetching latest release information..."
RELEASE_DATA=$(curl -s "$REPO_URL")
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch release data."
    exit 1
fi

# Extract the release tag
TAG=$(echo "$RELEASE_DATA" | grep -oP '"tag_name": "\K[^"]+')
if [ -z "$TAG" ]; then
    echo "Error: Failed to extract release tag."
    exit 1
fi

# Find the asset URL for "Scrappy_{tag}_update.muxapp"
ASSET_URL=$(echo "$RELEASE_DATA" | grep -oP '"browser_download_url": "\K[^"]+Scrappy_'${TAG}'_update\.muxapp')
if [ -z "$ASSET_URL" ]; then
    # If "Scrappy_{tag}_update.muxapp" is not found, look for any "Scrappy_{tag}*.muxapp"
    ASSET_URL=$(echo "$RELEASE_DATA" | grep -oP '"browser_download_url": "\K[^"]+Scrappy_'${TAG}'[^"]*\.muxapp')
    if [ -z "$ASSET_URL" ]; then
        echo "Error: No matching asset found for tag $TAG."
        exit 1
    fi
fi

# Download the asset
echo "Downloading asset: $ASSET_URL"
ASSET_NAME=$(basename "$ASSET_URL")
curl -L -o "$TEMP_DIR/$ASSET_NAME" "$ASSET_URL"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download asset."
    exit 1
fi

# Unzip the asset into the target directory
echo "Unzipping $ASSET_NAME to $TARGET_DIR..."
unzip -o "$TEMP_DIR/$ASSET_NAME" -d "$TARGET_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Failed to unzip asset."
    exit 1
fi

# Clean up temporary files
rm -rf "$TEMP_DIR"

echo "Success: Scrappy updated to version $TAG."
echo "Please restart the app to apply the update."
exit 0
