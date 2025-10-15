#!/bin/bash
# HELP: Scrappy
# ICON: scrappy
# GRID: Scrappy

. /opt/muos/script/var/func.sh

# Define global variables
SCREEN_WIDTH=$(GET_VAR device mux/width)
SCREEN_HEIGHT=$(GET_VAR device mux/height)
SCREEN_RESOLUTION="${SCREEN_WIDTH}x${SCREEN_HEIGHT}"

if pgrep -f "playbgm.sh" >/dev/null; then
	killall -q "playbgm.sh" "mpg123"
fi

echo app >/tmp/act_go

LOVEDIR="$MUOS_STORE_DIR/application/Scrappy/.scrappy"
GPTOKEYB="$(GET_VAR "device" "storage/rom/mount")/MUOS/emulator/gptokeyb/gptokeyb2.armhf"
STATICDIR="$LOVEDIR/static/"
BINDIR="$LOVEDIR/bin"

# Export environment variables
SETUP_SDL_ENVIRONMENT
export SDL_GAMECONTROLLERCONFIG_FILE="/usr/lib/gamecontrollerdb.txt"
export XDG_DATA_HOME="$STATICDIR"
export HOME="$STATICDIR"
export LD_LIBRARY_PATH="$BINDIR/libs.aarch64:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$BINDIR/plugins"

# Ensure glyphs are mirrored to SD1 so icon resolves from primary storage
PRIMARY_APP_DIR="$(GET_VAR "device" "storage/rom/mount")/MUOS/application"
# Derive the app root (Scrappy) from LOVEDIR which points to Scrappy/.scrappy
APP_DIR="$(dirname "$LOVEDIR")"
SRC_GLYPH_DIR="$APP_DIR/glyph"
DEST_APP_DIR="$PRIMARY_APP_DIR/Scrappy"
DEST_GLYPH_DIR="$DEST_APP_DIR/glyph"
# Only mirror when installed outside SD1 (APP_DIR not prefixed by PRIMARY_APP_DIR)
case "$APP_DIR/" in
  "$PRIMARY_APP_DIR"/*)
    : # Installed on SD1; no-op
    ;;
  *)
    if [ -d "$SRC_GLYPH_DIR" ]; then
      mkdir -p "$DEST_GLYPH_DIR" 2>/dev/null || true
      cp -rf "$SRC_GLYPH_DIR"/. "$DEST_GLYPH_DIR"/ 2>/dev/null || true
    fi
    ;;
esac

# Create Skyscraper folders
mkdir -p $HOME/.skyscraper/resources
cp -r $LOVEDIR/templates/resources/* $HOME/.skyscraper/resources

# Launcher
cd "$LOVEDIR" || exit
SET_VAR "system" "foreground_process" "love"

# Run Application
$GPTOKEYB "love" &
./bin/love . "${SCREEN_RESOLUTION}"

kill -9 "$(pidof gptokeyb2.armhf)"
