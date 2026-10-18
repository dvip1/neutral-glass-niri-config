#!/usr/bin/env bash
# Link packages into $HOME with GNU stow.
#   ./install.sh              link every package
#   ./install.sh niri waybar  link only these
# Stow refuses to overwrite a real file, so move/back up anything already there first.
set -euo pipefail
cd "$(dirname "$0")"
pkgs=("$@")
[[ ${#pkgs[@]} -eq 0 ]] && mapfile -t pkgs < <(find . -maxdepth 1 -mindepth 1 -type d -not -name '.*' -printf '%f\n' | sort)
stow -t "$HOME" -R -v "${pkgs[@]}"
