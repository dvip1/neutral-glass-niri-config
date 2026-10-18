# dotfiles

<video src="out.mp4" controls autoplay muted loop width="720"></video>

Managed with [GNU stow](https://www.gnu.org/software/stow/). Every top-level folder is a
**package** that mirrors the layout of `$HOME`, e.g. `niri/.config/niri/config.kdl` is linked to
`~/.config/niri/config.kdl`. The real files live here, so `git` tracks every change.

```sh
cd ~/.dotfiles
./install.sh                # link everything      (= stow -t ~ -R <every package>)
./install.sh niri waybar    # link only some
stow -D -t ~ waybar         # unlink one package (files stay in the repo)
git status / git diff       # see what changed in any package
```

To add a new tool: move its config into `~/.dotfiles/<tool>/<same path as under $HOME>`,
then `./install.sh <tool>`.

## Packages

| Package | What |
|---|---|
| niri, waybar, fuzzel, swaync, swayosd, swaylock | the desktop |
| theme | central theming (`theme.toml`, templates, the `theme` engine): see `theme/.config/theme/README.md` |
| kitty, alacritty, tmux | terminals and multiplexer |
| nvim | **its own git repo** (`dvip1/nvim-config`), only linked here, not tracked by this repo |
| bin | my scripts in `~/.local/bin` (theme, setwall, bt-menu, wifi-menu, clip-menu, win-menu, shortcuts) |
| desktop-entries | launcher entries for those scripts (they hold absolute `/home/dvip/...` paths) |
| git, easyeffects, mako | misc |

## Notes

- **Generated files are tracked.** `theme apply` rewrites `waybar/style.css`, `swaync/style.css`,
  `swayosd/style.css`, `fuzzel.ini`, `swaylock/config` and `theme/.../out/niri.kdl`. Toggling
  dark/light therefore shows up in `git status`. Edit `theme.toml` / `templates/`, not those files.
- **Directories are linked as a whole** (stow "folding"), so tools that save by rename keep writing
  into the repo. Single files (`.zshrc`, `.tmux.conf`, ...) are linked one by one.
- **Not here on purpose:** shell rc files (`.zshrc`, `.bashrc`, ...), fish, ghostty, zellij, htop and gtk-3.0 (left as plain files in `$HOME`), tmux plugins (`~/.tmux/plugins`, let tpm fetch them), `~/.oh-my-zsh`,
  shell history, `alacritty/themes` (a 56 MB clone, git-ignored), `mimeapps.list` (GLib rewrites it by
  rename, which would replace the link), browser/app data, and anything with credentials (`~/.config/gh`).
- Before pushing this anywhere public, re-check for secrets: `git grep -inE 'token|secret|password|api.?key'`.
