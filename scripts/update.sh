#!/bin/sh
# Scrappy Update Script

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use python3 updater for reliable JSON parsing and unzipping
if command -v python3 >/dev/null 2>&1; then
    exec python3 "$SCRIPT_DIR/update.py"
fi

echo "Error: python3 is required for updating Scrappy."
exit 1
