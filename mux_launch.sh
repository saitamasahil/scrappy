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

# Define paths and commands
LOVEDIR="$MUOS_STORE_DIR/application/Scrappy/.scrappy"
GPTOKEYB="$(GET_VAR "device" "storage/rom/mount")/MUOS/emulator/gptokeyb/gptokeyb2.armhf"
STATICDIR="$LOVEDIR/static/"
BINDIR="$LOVEDIR/bin"

# Export environment variables
SETUP_SDL_ENVIRONMENT
export XDG_DATA_HOME="$STATICDIR"
export HOME="$STATICDIR"
export LD_LIBRARY_PATH="$BINDIR/libs.aarch64:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$BINDIR/plugins"

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
