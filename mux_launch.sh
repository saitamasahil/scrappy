#!/bin/sh
# HELP: Scrappy
# ICON: scrappy
# GRID: Scrappy

STAGE_OVERLAY=0 . /opt/muos/script/var/func.sh

# Check for SETUP_APP (Jacaranda or newer)
if command -v SETUP_APP >/dev/null 2>&1; then
    # --- Jacaranda Logic ---
    APP_BIN="bin/love"
    SETUP_APP "love" ""

    APP_DIR="/run/muos/storage/application/Scrappy"
    cd "$APP_DIR/.scrappy" || exit

    export SDL_GAMECONTROLLERCONFIG_FILE="/usr/lib/gamecontrollerdb.txt"
    export XDG_DATA_HOME="$APP_DIR/.scrappy/static"
    export HOME="$APP_DIR/.scrappy/static"
    export LD_LIBRARY_PATH="$APP_DIR/.scrappy/bin/libs.aarch64:$LD_LIBRARY_PATH"
    export QT_PLUGIN_PATH="$APP_DIR/.scrappy/bin/plugins"

    mkdir -p "$HOME/.skyscraper/resources"
    cp -r "$APP_DIR/.scrappy/templates/resources/"* "$HOME/.skyscraper/resources/" 2>/dev/null || true

    if pgrep -f "playbgm.sh" >/dev/null; then
        killall -q "playbgm.sh" "mpg123"
    fi

    GPTOKEYB="$(GET_VAR "device" "storage/rom/mount")/MUOS/emulator/gptokeyb/gptokeyb2.armhf"
    SCREEN_WIDTH="$(GET_VAR device mux/width)"
    SCREEN_HEIGHT="$(GET_VAR device mux/height)"
    SCREEN_RESOLUTION="${SCREEN_WIDTH}x${SCREEN_HEIGHT}"

    $GPTOKEYB "love" &
    ./bin/love . "${SCREEN_RESOLUTION}"
    kill -9 "$(pidof gptokeyb2.armhf)" 2>/dev/null || true

else
    # --- Legacy Logic (Loose Goose / Older) ---

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

    SETUP_SDL_ENVIRONMENT
    export SDL_GAMECONTROLLERCONFIG_FILE="/usr/lib/gamecontrollerdb.txt"
    export XDG_DATA_HOME="$STATICDIR"
    export HOME="$STATICDIR"
    export LD_LIBRARY_PATH="$BINDIR/libs.aarch64:$LD_LIBRARY_PATH"
    export QT_PLUGIN_PATH="$BINDIR/plugins"

    # Mirror glyphs (Legacy requirement)
    PRIMARY_APP_DIR="$(GET_VAR "device" "storage/rom/mount")/MUOS/application"
    APP_DIR="$(dirname "$LOVEDIR")"
    SRC_GLYPH_DIR="$APP_DIR/glyph"
    DEST_APP_DIR="$PRIMARY_APP_DIR/Scrappy"
    DEST_GLYPH_DIR="$DEST_APP_DIR/glyph"

    case "$APP_DIR/" in
    "$PRIMARY_APP_DIR"/*) : ;;
    *)
        if [ -d "$SRC_GLYPH_DIR" ]; then
            mkdir -p "$DEST_GLYPH_DIR" 2>/dev/null || true
            cp -rf "$SRC_GLYPH_DIR"/. "$DEST_GLYPH_DIR"/ 2>/dev/null || true
        fi
        ;;
    esac

    mkdir -p "$HOME/.skyscraper/resources"
    cp -r "$LOVEDIR/templates/resources/"* "$HOME/.skyscraper/resources/" 2>/dev/null || true

    cd "$LOVEDIR" || exit
    SET_VAR "system" "foreground_process" "love"

    $GPTOKEYB "love" &
    ./bin/love . "${SCREEN_RESOLUTION}"
    kill -9 "$(pidof gptokeyb2.armhf)" 2>/dev/null || true
fi
