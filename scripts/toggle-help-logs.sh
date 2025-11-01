#!/usr/bin/env bash
set -euo pipefail

# Toggle Skyscraper --help logging by editing BOTH files in-place:
# - lib/skyscraper.lua        (fetch_single)
# - scenes/main.lua           (scrape_platforms)
# Usage: scripts/toggle-help-logs.sh enable|disable

MODE=${1:-}
if [[ -z "$MODE" || ("$MODE" != "enable" && "$MODE" != "disable") ]]; then
  echo "Usage: $0 enable|disable" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

SKY_FILE="lib/skyscraper.lua"
MAIN_FILE="scenes/main.lua"

# Keep backups OUTSIDE scenes/ so Love doesn't try to load them
BACKUP_DIR="scripts/.backups"
SKY_BAK="$BACKUP_DIR/lib_skyscraper.lua.bak"
MAIN_BAK="$BACKUP_DIR/scenes_main.lua.bak"

if [[ "$MODE" == "enable" ]]; then
  echo "Enabling help-logs ..."
  mkdir -p "$BACKUP_DIR"
  # Clean legacy backups that break loader
  [[ -f "scenes/main.lua.bak-help" ]] && rm -f "scenes/main.lua.bak-help"
  # Backups (only once)
  [[ -f "$SKY_BAK" ]] || cp -f "$SKY_FILE" "$SKY_BAK"
  [[ -f "$MAIN_BAK" ]] || cp -f "$MAIN_FILE" "$MAIN_BAK"

  # 1) Modify lib/skyscraper.lua (inject nativefs require if missing and replace fetch_single)
  awk '
BEGIN { in_fetch=0; have_nativefs=0 }
{
  if ($0 ~ /^local[[:space:]]+nativefs[[:space:]]*=/) { have_nativefs=1 }
}
$0 ~ /^local[[:space:]]+channels[[:space:]]*=/ {
  print $0
  if (have_nativefs==0) { print "local nativefs          = require(\"lib.nativefs\")"; have_nativefs=1; next }
  next
}
$0 ~ /^function[[:space:]]+skyscraper\.fetch_single\(/ { in_fetch=1; next }
in_fetch==1 && $0 ~ /^end[[:space:]]*$/ {
  in_fetch=0;
  print "function skyscraper.fetch_single(rom_path, rom, input_folder, platform, ...)";
  print "  local function run_help_and_log()";
  print "    local ts = os.date(\"%Y%m%d_%H%M%S\")";
  print "    local help_log = string.format(\"logs/skyscraper-help-%s.log\", ts)";
  print "    if not nativefs.getInfo(\"logs\") then nativefs.createDirectory(\"logs\") end";
  print "    local cmd = string.format(\"%s --help\", skyscraper.base_command)";
  print "    log.write(string.format(\"[help] Executing: %s\", cmd), \"skyscraper\")";
  print "    local handle = io.popen(cmd .. \" 2>&1\", \"r\")";
  print "    if not handle then";
  print "      log.write(\"[help] Failed to execute Skyscraper --help\", \"skyscraper\")";
  print "      nativefs.write(help_log, \"Failed to execute Skyscraper --help\\n\")";
  print "      return";
  print "    end";
  print "    local out = handle:read(\"*a\") or \"\"";
  print "    handle:close()";
  print "    nativefs.write(help_log, out)";
  print "    if out ~= \"\" then";
  print "      for line in out:gmatch(\"([^\\n]*)\\n?\") do";
  print "        if line ~= \"\" then log.write(string.format(\"[help] %s\", line), \"skyscraper\") end";
  print "      end";
  print "    end";
  print "    channels.SKYSCRAPER_OUTPUT:push({ log = \"[help] Skyscraper --help output written to \" .. help_log })";
  print "  end";
  print "  run_help_and_log()";
  print "  return";
  print "end";
  next
}
in_fetch==0 { print $0 }
' "$SKY_FILE" > "$SKY_FILE.tmp" && mv -f "$SKY_FILE.tmp" "$SKY_FILE"

  # 2) Modify scenes/main.lua by inserting exact block from template after function line
  if ! grep -q "run_help_and_log_once" "$MAIN_FILE"; then
    HOOK_FILE="scripts/templates/scrape_hook_block.lua"
    if [[ ! -f "$HOOK_FILE" ]]; then echo "Missing $HOOK_FILE" >&2; exit 5; fi
    LINE_NO=$(awk '/^local[[:space:]]+function[[:space:]]+scrape_platforms\(/ { print NR; exit }' "$MAIN_FILE")
    if [[ -z "$LINE_NO" ]]; then echo "scrape_platforms() not found in $MAIN_FILE" >&2; exit 6; fi
    head -n "$LINE_NO" "$MAIN_FILE" > "$MAIN_FILE.tmp"
    cat "$HOOK_FILE" >> "$MAIN_FILE.tmp"
    tail -n +$((LINE_NO+1)) "$MAIN_FILE" >> "$MAIN_FILE.tmp"
    mv -f "$MAIN_FILE.tmp" "$MAIN_FILE"
  fi

  echo "Done. Help logging ENABLED in both files."
else
  echo "Disabling help-logs (restoring originals) ..."
  # Handle legacy backup inside scenes/ that breaks loader
  if [[ -f "scenes/main.lua.bak-help" ]]; then
    mv -f "scenes/main.lua.bak-help" "$MAIN_FILE"
    echo "Restored legacy backup to $MAIN_FILE and removed .bak-help file."
  elif [[ -f "$MAIN_BAK" ]]; then
    mv -f "$MAIN_BAK" "$MAIN_FILE"; echo "Restored $MAIN_FILE"
  else
    echo "No backup for $MAIN_FILE" >&2
  fi

  if [[ -f "$SKY_BAK" ]]; then
    mv -f "$SKY_BAK" "$SKY_FILE"; echo "Restored $SKY_FILE"
  else
    echo "No backup for $SKY_FILE" >&2
  fi
  echo "Done. Help logging DISABLED."
fi
