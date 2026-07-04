#!/bin/bash
# shellcheck shell=bash
set -e

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build options
BUILD_FULL=true
BUILD_UPDATE=true

usage() {
    echo "Usage: bash build.sh [option]"
    echo "Options:"
    echo "  1, --full     Build ONLY the full package"
    echo "  2, --update   Build ONLY the update package"
    echo "  (none)        Build BOTH packages (default)"
    echo "  -h, --help    Show this help message"
}

# Parse arguments
case "$1" in
    1|--full)
        BUILD_UPDATE=false
        ;;
    2|--update)
        BUILD_FULL=false
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    "")
        # Default: build both
        ;;
    *)
        echo "Error: Unknown option '$1'"
        usage
        exit 1
        ;;
esac

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

# Copy all necessary files (Base files for both packages)
echo "Copying base files..."
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
cp "$PROJECT_ROOT/theme_light.ini" "$WORKDIR/Scrappy/.scrappy/"
cp "$PROJECT_ROOT/theme_classic.ini" "$WORKDIR/Scrappy/.scrappy/"
cp "$PROJECT_ROOT/theme_light_classic.ini" "$WORKDIR/Scrappy/.scrappy/"

# Copy assets and ensure the directory exists
mkdir -p "$WORKDIR/Scrappy/.scrappy/assets"
if [ -d "$PROJECT_ROOT/assets" ]; then
    echo "Copying assets..."
    (
        shopt -s dotglob
        cp -r "$PROJECT_ROOT/assets/"* "$WORKDIR/Scrappy/.scrappy/assets/" 2>/dev/null || true
    )
fi

# Ensure glyph directory exists in the root of the app and copy logo_scrappy.svg
mkdir -p "$WORKDIR/Scrappy/glyph"
if [ -f "$PROJECT_ROOT/assets/glyph/logo_scrappy.svg" ]; then
    echo "Copying logo_scrappy.svg to glyph directory..."
    cp "$PROJECT_ROOT/assets/glyph/logo_scrappy.svg" "$WORKDIR/Scrappy/glyph/"
else
    echo "Warning: logo_scrappy.svg not found in assets/glyph"
fi

if [ "$BUILD_UPDATE" = true ]; then
    # Create update package
    echo "Creating update package..."
    (cd "$WORKDIR" && zip -qr "$UPDATE" ./Scrappy)
fi

if [ "$BUILD_FULL" = true ]; then
    # Copy additional files for full package
    echo "Copying additional files for full package..."
    cp -r "$PROJECT_ROOT/bin" "$WORKDIR/Scrappy/.scrappy/"
    cp -r "$PROJECT_ROOT/data" "$WORKDIR/Scrappy/.scrappy/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/logs" "$WORKDIR/Scrappy/.scrappy/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/sample" "$WORKDIR/Scrappy/.scrappy/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/showcase" "$WORKDIR/Scrappy/.scrappy/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/static" "$WORKDIR/Scrappy/.scrappy/"



    # Create full package
    echo "Creating full package..."
    (cd "$WORKDIR" && zip -qr "$FULL" ./Scrappy)
fi

# Clean up
rm -rf "$WORKDIR"

echo -e "\nBuild complete!"
[ "$BUILD_FULL" = true ] && [ -f "$FULL" ] && ls -lh "$FULL"
[ "$BUILD_UPDATE" = true ] && [ -f "$UPDATE" ] && ls -lh "$UPDATE"
