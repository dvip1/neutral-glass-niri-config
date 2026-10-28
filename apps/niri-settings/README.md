# niri-settings

A small Qt6 (Widgets, C++) settings window for this desktop. Starts in ~0.2 s, ~45 MB (PSS).

    niri-settings [appearance|power|theme|shortcuts]     a second launch switches the open window to that page

| Page | What it changes |
|---|---|
| Appearance | dark style, theme (`theme set`), wallpaper (`setwall`; thumbnails cached in `~/.cache/niri-settings/thumbs`) |
| Power & Idle | `~/.config/power/power.conf`, edited line by line (comments kept); the `idle` daemon reloads it |
| Theme Details | blur, opacities, radii, gaps, font, motion of the current theme: `theme setkey` / `theme unset` (only that line of `themes/NAME.toml` changes) |
| Shortcuts & More | do not disturb, restart Quickshell, open config files in nvim, searchable niri key list (`shortcuts --print`) |

Look: `~/.config/theme/out/settings.qss`, generated from `~/.config/theme/templates/settings.qss` (`set_*` colours in
`theme.toml [derive]`); the app reloads it when it changes. niri blurs behind it (window rule in `templates/niri.kdl`).

Build: `./build.sh` (needs `qt6-qtbase-devel`, cmake, ninja, g++); installs to `~/.local/lib/niri-settings/` with a link in `~/.local/bin`
(the launcher entry uses the lib path: the launcher hides entries that run something in `~/.local/bin`).
Opened by: launcher entry "Niri Settings", Mod+S, quick settings gear (Power page).
