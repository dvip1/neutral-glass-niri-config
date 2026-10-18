#!/usr/bin/env bash
# Syncs ~/.config/alacritty/theme.toml and ~/.config/zellij/config.kdl with
# the current GNOME light/dark color-scheme. Alacritty's live-config-reload
# picks up its change instantly; Zellij picks up its change the next time a
# new session is started (it doesn't hot-reload theme on running sessions).
set -euo pipefail

THEME_DIR="$HOME/.config/alacritty/custom-themes"
TARGET="$HOME/.config/alacritty/theme.toml"

DARK_THEME="$THEME_DIR/hallownest.toml"
LIGHT_THEME="$THEME_DIR/pharloom.toml"

ZELLIJ_CONFIG="$HOME/.config/zellij/config.kdl"

scheme=$(gsettings get org.gnome.desktop.interface color-scheme | tr -d "'")

if [[ "$scheme" == "prefer-dark" ]]; then
    source_theme="$DARK_THEME"
    zellij_theme="hallownest"
else
    source_theme="$LIGHT_THEME"
    zellij_theme="pharloom"
fi

if ! cmp -s "$source_theme" "$TARGET" 2>/dev/null; then
    cp "$source_theme" "$TARGET"
fi

if [[ -f "$ZELLIJ_CONFIG" ]]; then
    sed -i -E "s/^theme \"[^\"]*\"/theme \"$zellij_theme\"/" "$ZELLIJ_CONFIG"
fi
