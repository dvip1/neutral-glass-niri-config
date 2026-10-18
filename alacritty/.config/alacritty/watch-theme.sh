#!/usr/bin/env bash
# Runs auto-theme.sh once immediately, then again every time GNOME's
# color-scheme setting changes (dark <-> light).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/auto-theme.sh"

gsettings monitor org.gnome.desktop.interface color-scheme | while read -r _; do
    "$SCRIPT_DIR/auto-theme.sh"
done
