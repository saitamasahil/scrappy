#!/bin/bash

# Variables
REPO_URL="https://api.github.com/repos/gabrielfvale/scrappy/releases/latest"
TARGET_DIR="/mnt/mmc/MUOS/application"
TEMP_DIR=$(mktemp -d)

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
exit 0
