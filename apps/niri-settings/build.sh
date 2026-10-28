#!/usr/bin/env bash
# Build niri-settings and install it to ~/.local/lib/niri-settings, linked from ~/.local/bin
# (needs qt6-qtbase-devel, cmake, ninja, g++). The launcher entry points at the lib path: the
# Quickshell launcher hides entries whose command is in ~/.local/bin (those are scripts).
set -euo pipefail
cd "$(dirname "$0")"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build
install -Dm755 -s build/niri-settings "$HOME/.local/lib/niri-settings/niri-settings"
ln -sfn "$HOME/.local/lib/niri-settings/niri-settings" "$HOME/.local/bin/niri-settings"
echo "installed ~/.local/lib/niri-settings/niri-settings (+ link in ~/.local/bin)"
