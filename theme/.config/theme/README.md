# Central theme

Everything about how the desktop looks (fonts, corner radius, focus ring, every
colour in dark and light) lives in **`theme.toml`**. Change it, run one command:

    theme apply          # regenerate every app's config and reload them
    theme toggle         # flip dark <-> light  (also: theme dark / theme light)
    theme status -v      # current mode + what gets generated
    theme edit           # open theme.toml in $EDITOR

## What is generated (don't edit these by hand, they get overwritten)

| App | Generated file |
|---|---|
| waybar | `~/.config/waybar/style.css` |
| notifications (swaync) | `~/.config/swaync/style.css` |
| volume popup (swayosd) | `~/.config/swayosd/style.css` |
| launcher + menus (fuzzel) | `~/.config/fuzzel/fuzzel.ini` |
| lock screen (swaylock) | `~/.config/swaylock/config` |
| niri (ring colour, rounded corners, blur rules) | `~/.config/theme/out/niri.kdl`, included by `~/.config/niri/config.kdl` |
| kitty | `~/.config/kitty/{dark,light,no-preference}-theme.auto.conf`, taken from kitty's own theme collection (`[kitty]` in `theme.toml`; browse names with `kitten themes`) |

Each one is rendered from a template in `templates/`. To change *layout* (padding,
which element has a pill, etc.) edit the template; to change *colours, fonts or
radii* edit `theme.toml`.

## Template syntax

`{{name}}` is replaced by a value from `theme.toml`. Colours come out as CSS
(`rgba(...)`) by default; add a filter for other formats:

- `{{name|hex}}`   rrggbbaa   (fuzzel)
- `{{name|hex6}}`  rrggbb     (swaylock)
- `{{name|hash8}}` #rrggbbaa  (niri)

Unknown names stop `theme apply` before anything is written.

## Other apps

- **kitty** colours come from kitty's own themes (see the `[kitty]` section); kitty switches between the dark and
  light file by itself when the system colour scheme changes. Its opacity is in `~/.config/kitty/kitty.conf`.
- **GTK4 / libadwaita apps** (Files, ...) follow the system colour scheme, which
  `theme dark/light/toggle` sets. They have no per-colour settings here.
- **Wallpaper** is separate (`setwall`).
