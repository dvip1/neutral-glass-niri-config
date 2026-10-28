# Central theme

The desktop has several **themes** (`themes/*.toml`, one file each), every one in a dark and a light
mode. A theme sets fonts, corner radii, gaps, blur on/off, transparency, kitty's colour theme and opacity,
the GTK accent and all colours, and one command rewrites every app's config from it:

    theme list           the themes (current one marked)       also: the "Change Theme" launcher entry (theme-menu)
    theme set gruvbox    switch theme (keeps dark/light)       theme next / theme prev cycle
    theme toggle         flip dark <-> light                   also: theme dark / theme light
    theme apply          regenerate after editing a theme or template
    theme status -v      current theme + mode and what gets generated
    theme edit [NAME]    open a theme file in $EDITOR

The current theme is remembered in `~/.local/state/theme/current` (default `glass`); the mode in
`gsettings org.gnome.desktop.interface color-scheme`.

| Theme | Look |
|---|---|
| glass | neutral frosted glass, no tint (the original; every colour hand-set) |
| rose-pine | Rosé Pine / Dawn: muted purple glass, rose accent, rounder, Inter |
| gruvbox | warm retro, solid panels, no blur, small corners, JetBrains Mono |
| everforest | green-grey forest tones, light glass |
| mono | stark black/white, flat, no blur, sharp corners, JetBrains Mono |

## Making a theme

Copy one of `themes/*.toml`. A theme only needs a description and, per mode, eight base colours:

    [dark]
    bg = "#282828"; surface = "#32302f"; fg = "#ebdbb2"; fg_muted = "#928374"
    accent = "#fabd2f"; c_crit = "#fb4934"; c_warn = "#fe8019"; c_ok = "#b8bb26"

Every other colour (about 60: bar, pills, launcher, OSD, focus ring, lock screen...) is made from those by
the formulas in `[derive]` in `theme.toml`, e.g. `bar_bg = "bg @ alpha_bar"`, `fg_title = "mix(fg, fg_muted, 0.4)"`.
Set any of those names in the theme to override it. Anything else the theme leaves out (`[font]`, `[shape]`,
`[effects]`, `[opacity]`, `[motion]`, `[kitty]`) comes from `theme.toml`. Numbers inside `[dark]`/`[light]`
override `[opacity]` alphas for that mode only. `[gtk] accent` sets libadwaita's accent colour.

## What is generated (don't edit these by hand, they get overwritten)

| App | Generated file |
|---|---|
| bar (Quickshell) | `~/.config/quickshell/Theme.qml` (colours as `#aarrggbb` via the `|qml` filter; Quickshell reloads by itself) |
| waybar (old bar) | `~/.config/waybar/style.css` |
| notifications (swaync) | `~/.config/swaync/style.css` |
| volume popup (swayosd) | `~/.config/swayosd/style.css` |
| launcher + menus (fuzzel) | `~/.config/fuzzel/fuzzel.ini` |
| lock screen (swaylock) | `~/.config/swaylock/config` |
| niri (ring colour, gaps, rounded corners, blur rules) | `~/.config/theme/out/niri.kdl`, included by `~/.config/niri/config.kdl` |
| niri window animations (shader corner radius) | `~/.config/niri/animations.kdl` |
| kitty | `~/.config/kitty/{dark,light,no-preference}-theme.auto.conf`, taken from kitty's own theme collection (`[kitty]`; browse names with `kitten themes`) and `theme.conf` (opacity) |

Each one is rendered from a template in `templates/`. To change *layout* (padding,
which element has a pill, etc.) edit the template; to change *colours, fonts or
radii* edit the theme. Hover/press timings and the spring curve are in `[motion]`.

## Template syntax

`{{name}}` is replaced by a value from the theme (also `{{theme}}`, `{{mode}}`, `{{gaps}}`, `{{blur}}`, `{{kitty_opacity}}`). Colours come out as CSS
(`rgba(...)`) by default; add a filter for other formats:

- `{{name|hex}}`   rrggbbaa   (fuzzel)
- `{{name|hex6}}`  rrggbb     (swaylock)
- `{{name|hash8}}` #rrggbbaa  (niri)

Unknown names stop `theme apply` before anything is written.

## Other apps

- **kitty** colours come from kitty's own themes (see the `[kitty]` section); kitty switches between the dark and
  light file by itself when the system colour scheme changes. Opacity changes reach kitty windows opened
  after `dynamic_background_opacity` was added (2026-10-28); older windows keep theirs until restarted.
- **GTK4 / libadwaita apps** (Files, ...) follow the system colour scheme, which
  `theme dark/light/toggle` sets, and get the theme's `[gtk] accent` (shared with GNOME). Nothing else.
- **GTK3 apps** get the theme's full colours: `templates/gtk3.css` (adw-gtk3 + `gtk_*` colours from `[derive]`)
  becomes the GTK3 theme "Niri" (`out/gtk/Niri`, linked into `~/.local/share/themes` as `Niri` and `Niri-alt`).
  Only under niri: `theme` (and `theme gtk3` at niri startup) sets gsettings `gtk-theme`, flipping between the two
  names so running apps reload live. GNOME resets it to Adwaita at login (`~/.config/autostart/gtk-theme-gnome.desktop`).
  `GTK_THEME` is NOT used: it makes libadwaita apps lose the accent colour. Needs `adw-gtk3-theme` (dnf).
- **Folder icons** (Files, file pickers): icon theme "Niri" = Adwaita with its folder / home / desktop / bookmarks
  icons recoloured (`templates/folders/`, copied from Adwaita 50 with the blues replaced by `folder*` tokens; `folder`
  defaults to the accent, glass and mono set a grey). Same niri-only switching as GTK3 (gsettings `icon-theme`).
- **Wallpaper** is separate (`setwall`).
