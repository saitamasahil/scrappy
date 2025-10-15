#!/bin/bash
# shellcheck shell=bash
set -e

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create build directory if it doesn't exist
BUILD_DIR="$PROJECT_ROOT/build"
if [ ! -d "$BUILD_DIR" ]; then
    echo "Creating build directory: $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
fi

# Read version from globals.lua
MAJOR=$(grep -oP 'major = \K\d+' "$PROJECT_ROOT/globals.lua")
MINOR=$(grep -oP 'minor = \K\d+' "$PROJECT_ROOT/globals.lua")
PATCH=$(grep -oP 'patch = \K\d+' "$PROJECT_ROOT/globals.lua")

if [ -z "$MAJOR" ] || [ -z "$MINOR" ] || [ -z "$PATCH" ]; then
    echo "Error: Could not determine version from globals.lua"
    exit 1
fi

TAG="v${MAJOR}.${MINOR}.${PATCH}"
echo "Building version: $TAG"

# Set up paths
FULL="$BUILD_DIR/Scrappy_${TAG}.muxapp"
UPDATE="$BUILD_DIR/Scrappy_${TAG}_update.muxapp"
WORKDIR="$BUILD_DIR/pkg_${MAJOR}${MINOR}${PATCH}"

# Clean up old build
rm -rf "$WORKDIR" "$FULL" "$UPDATE"
mkdir -p "$WORKDIR/Scrappy/.scrappy"

# Copy all necessary files
echo "Copying files..."
cp "$PROJECT_ROOT/mux_launch.sh" "$WORKDIR/Scrappy/"

# Copy core directories
cp -r "$PROJECT_ROOT/helpers" "$WORKDIR/Scrappy/.scrappy/"
cp -r "$PROJECT_ROOT/lib" "$WORKDIR/Scrappy/.scrappy/"
cp -r "$PROJECT_ROOT/scenes" "$WORKDIR/Scrappy/.scrappy/"
cp -r "$PROJECT_ROOT/scripts" "$WORKDIR/Scrappy/.scrappy/" 2>/dev/null || true
cp -r "$PROJECT_ROOT/templates" "$WORKDIR/Scrappy/.scrappy/"

# Copy configuration files
cp "$PROJECT_ROOT/conf.lua" "$WORKDIR/Scrappy/.scrappy/"
cp "$PROJECT_ROOT/globals.lua" "$WORKDIR/Scrappy/.scrappy/"
cp "$PROJECT_ROOT/main.lua" "$WORKDIR/Scrappy/.scrappy/"
cp "$PROJECT_ROOT/config.ini.example" "$WORKDIR/Scrappy/.scrappy/"
cp "$PROJECT_ROOT/skyscraper_config.ini.example" "$WORKDIR/Scrappy/.scrappy/"
cp "$PROJECT_ROOT/theme.ini" "$WORKDIR/Scrappy/.scrappy/"

# Copy assets and ensure the directory exists
mkdir -p "$WORKDIR/Scrappy/.scrappy/assets"
if [ -d "$PROJECT_ROOT/assets" ]; then
    echo "Copying assets..."
    # Copy all contents of assets, including hidden files
    (shopt -s dotglob; cp -r "$PROJECT_ROOT/assets/"* "$WORKDIR/Scrappy/.scrappy/assets/" 2>/dev/null || true)
fi

# Ensure glyph directory exists in the root of the app and copy scrappy.png
mkdir -p "$WORKDIR/Scrappy/glyph"
GLYPH_SRC=""
if [ -f "$PROJECT_ROOT/assets/scrappy.png" ]; then
    GLYPH_SRC="$PROJECT_ROOT/assets/scrappy.png"
elif [ -f "$PROJECT_ROOT/glyph/scrappy.png" ]; then
    GLYPH_SRC="$PROJECT_ROOT/glyph/scrappy.png"
fi
if [ -n "$GLYPH_SRC" ]; then
    echo "Copying scrappy.png to glyph directory..."
    cp "$GLYPH_SRC" "$WORKDIR/Scrappy/glyph/"
    # Also copy into resolution-specific glyph folders so MUX can resolve per-resolution icons
    for res in 640x480 720x480 720x720 1024x768; do
        mkdir -p "$WORKDIR/Scrappy/glyph/$res"
        cp "$GLYPH_SRC" "$WORKDIR/Scrappy/glyph/$res/scrappy.png"
    done
else
    echo "Warning: scrappy.png not found in expected locations"
fi

# Create update package
echo "Creating update package..."
(cd "$WORKDIR" && zip -qr "$UPDATE" ./Scrappy)

# Copy additional files for full package
cp -r "$PROJECT_ROOT/bin" "$WORKDIR/Scrappy/.scrappy/"
cp -r "$PROJECT_ROOT/data" "$WORKDIR/Scrappy/.scrappy/" 2>/dev/null || true
cp -r "$PROJECT_ROOT/logs" "$WORKDIR/Scrappy/.scrappy/" 2>/dev/null || true
cp -r "$PROJECT_ROOT/sample" "$WORKDIR/Scrappy/.scrappy/" 2>/dev/null || true
cp -r "$PROJECT_ROOT/static" "$WORKDIR/Scrappy/.scrappy/"

# Copy any additional glyph files from assets/glyph if they exist
if [ -d "$PROJECT_ROOT/assets/glyph" ]; then
    echo "Copying additional glyph files from assets..."
    (shopt -s dotglob; cp -r "$PROJECT_ROOT/assets/glyph/"* "$WORKDIR/Scrappy/glyph/" 2>/dev/null || true)
fi

# Create full package
echo "Creating full package..."
(cd "$WORKDIR" && zip -qr "$FULL" ./Scrappy)

# Clean up
rm -rf "$WORKDIR"

echo -e "\nBuild complete! Created:"
ls -lh "$FULL"
ls -lh "$UPDATE"
