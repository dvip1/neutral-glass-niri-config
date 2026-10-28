#!/usr/bin/env python3
"""Central theme engine.  See ~/.config/theme/README.md.

  theme apply          render every template from the current theme and reload the apps
  theme toggle         flip dark <-> light
  theme dark | light   set a mode
  theme list           the themes in themes/ (the current one is marked)
  theme set NAME       switch to another theme (keeps the dark/light mode)
  theme next | prev    cycle through the themes
  theme gtk3           (niri startup) point GTK at the generated GTK3 + icon themes
  theme status [-v]    show the current theme + mode and what gets generated
  theme edit [NAME]    open a theme file (default: the current one) in $EDITOR
"""
import os
import re
import subprocess
import sys
import tempfile
import tomllib

ROOT = os.path.dirname(os.path.realpath(__file__))
BASE = os.path.join(ROOT, 'theme.toml')
THEMES = os.path.join(ROOT, 'themes')
STATE = os.path.join(os.environ.get('XDG_STATE_HOME') or os.path.expanduser('~/.local/state'), 'theme', 'current')
DEFAULT_THEME = 'glass'
SCHEMA = 'org.gnome.desktop.interface'


# ---------- colours ----------
def parse_colour(s):
    s = s.strip()
    m = re.fullmatch(r'#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?', s)
    if m:
        h, a = m.group(1), m.group(2)
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), int(a, 16) / 255 if a else 1.0)
    m = re.fullmatch(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([0-9.]+)\s*)?\)', s)
    if m:
        return (int(m.group(1)), int(m.group(2)), int(m.group(3)), float(m.group(4)) if m.group(4) else 1.0)
    raise ValueError(f'unreadable colour: {s!r}')


def fmt_colour(c, how):
    r, g, b, a = c
    a8 = round(a * 255)
    if how == 'css':
        if a8 == 255:
            return f'#{r:02x}{g:02x}{b:02x}'
        return f'rgba({r}, {g}, {b}, {round(a, 3):g})'
    if how == 'hex':      # rrggbbaa   (fuzzel)
        return f'{r:02x}{g:02x}{b:02x}{a8:02x}'
    if how == 'hex6':     # rrggbb     (swaylock)
        return f'{r:02x}{g:02x}{b:02x}'
    if how == 'hash6':    # #rrggbb    (SVG)
        return f'#{r:02x}{g:02x}{b:02x}'
    if how == 'hash8':    # #rrggbbaa  (niri)
        return f'#{r:02x}{g:02x}{b:02x}{a8:02x}'
    if how == 'qml':      # #aarrggbb  (quickshell / Qt)
        return f'#{a8:02x}{r:02x}{g:02x}{b:02x}'
    raise ValueError(f'unknown colour filter: {how}')


def split_args(s):
    """Split on commas that are not inside parentheses (rgba(...) literals contain commas)."""
    out, depth, cur = [], 0, ''
    for ch in s:
        depth += (ch == '(') - (ch == ')')
        if ch == ',' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += ch
    return out + [cur]


class Palette:
    """One mode's colours. A theme gives a few base colours (bg, surface, fg, fg_muted, accent, c_crit,
    c_warn, c_ok) and may set any role directly; every other role comes from a formula in [derive]:

        "fg @ 0.13"             fg with alpha 0.13 (or with a named alpha from [opacity]: "bg @ alpha_bar")
        "mix(fg, fg_muted, 0.4)" 40 % of the way from fg to fg_muted
        "on(accent)"            readable text on top of accent: near-black or white
        "#rrggbb", "rgba(...)"  a literal
    """

    def __init__(self, given, derive, alphas):
        self.given, self.derive, self.alphas = given, derive, alphas
        self.cache, self.busy = {}, set()

    def names(self):
        return set(self.given) | set(self.derive)

    def get(self, name):
        if name in self.cache:
            return self.cache[name]
        if name in self.busy:
            raise ValueError(f'colour "{name}" is defined in terms of itself')
        self.busy.add(name)
        if name in self.given:
            c = self.expr(self.given[name], name)
        elif name in self.derive:
            c = self.expr(self.derive[name], name)
        else:
            raise KeyError(name)
        self.busy.discard(name)
        self.cache[name] = c
        return c

    def alpha(self, s, where):
        s = s.strip()
        try:
            return float(s)
        except ValueError:
            pass
        if s in self.alphas:
            return float(self.alphas[s])
        raise ValueError(f'{where}: unknown alpha "{s}" (add it to [opacity])')

    def expr(self, s, where):
        s = s.strip()
        depth, at = 0, -1
        for i, ch in enumerate(s):                   # the last top-level "@" sets the alpha
            depth += (ch == '(') - (ch == ')')
            if ch == '@' and depth == 0:
                at = i
        if at >= 0:
            r, g, b, _ = self.expr(s[:at], where)
            return (r, g, b, self.alpha(s[at + 1:], where))
        m = re.fullmatch(r'mix\((.*)\)', s)
        if m:
            args = split_args(m.group(1))
            if len(args) != 3:
                raise ValueError(f'{where}: mix() takes (a, b, amount): {s!r}')
            a, b, t = self.expr(args[0], where), self.expr(args[1], where), self.alpha(args[2], where)
            return tuple(round(x + (y - x) * t) for x, y in zip(a[:3], b[:3])) + (a[3] + (b[3] - a[3]) * t,)
        m = re.fullmatch(r'on\((.*)\)', s)
        if m:
            r, g, b, _ = self.expr(m.group(1), where)
            lum = sum(w * ((c / 255) / 12.92 if c <= 10 else ((c / 255 + 0.055) / 1.055) ** 2.4)
                      for w, c in zip((0.2126, 0.7152, 0.0722), (r, g, b)))
            return (0, 0, 0, 0.8) if lum > 0.18 else (255, 255, 255, 1.0)
        if s.startswith('#') or s.startswith('rgb'):
            return parse_colour(s)
        if re.fullmatch(r'[A-Za-z0-9_]+', s):
            try:
                return self.get(s)
            except KeyError:
                raise ValueError(f'{where}: refers to "{s}", which the theme does not define') from None
        raise ValueError(f'{where}: unreadable colour {s!r}')


# ---------- state ----------
def current_mode():
    out = subprocess.run(['gsettings', 'get', SCHEMA, 'color-scheme'], capture_output=True, text=True).stdout
    return 'dark' if 'prefer-dark' in out else 'light'


def themes():
    return sorted(f[:-5] for f in os.listdir(THEMES) if f.endswith('.toml'))


def current_theme():
    try:
        name = open(STATE).read().strip()
    except OSError:
        name = ''
    return name if name in themes() else DEFAULT_THEME


def merge(base, over):
    out = dict(base)
    for k, v in over.items():
        out[k] = merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


def load(name=None):
    """theme.toml (shared defaults, [derive] formulas, [targets]) with themes/NAME.toml on top."""
    name = name or current_theme()
    f = os.path.join(THEMES, name + '.toml')
    if not os.path.exists(f):
        raise ValueError(f'no theme "{name}" (have: {", ".join(themes())})')
    with open(BASE, 'rb') as b, open(f, 'rb') as t:
        cfg = merge(tomllib.load(b), tomllib.load(t))
    cfg['name'] = name
    return cfg


def context(cfg, mode):
    if mode not in cfg:            # a theme with only one mode uses it for both
        mode_cfg = cfg.get('dark') or cfg.get('light')
    else:
        mode_cfg = cfg[mode]
    fx = cfg.get('effects', {})
    ctx = {
        'theme': cfg['name'],
        'font': cfg['font']['family'],
        'icon_font': cfg['font']['icons'],
        'font_size': cfg['font']['size'],
        'bar_font_size': cfg['font']['bar_size'],
        'radius': cfg['shape']['radius'],
        'radius_large': cfg['shape']['radius_large'],
        'radius_pill': cfg['shape']['radius_pill'],
        'radius_small': cfg['shape']['radius_small'],
        'mode': mode,
        'ring_width': cfg['shape']['ring_width'],
        'gaps': cfg['shape'].get('gaps', 10),
        'blur': 'true' if fx.get('blur', True) else 'false',
        'kitty_opacity': fx.get('kitty_opacity', 0.8),
        'gtk3_base': 'adw-gtk3-dark' if mode == 'dark' else 'adw-gtk3',
        **cfg.get('motion', {}),
    }
    # the same spring for Qt: cubic-bezier(a, b, c, d) -> "a, b, c, d" (QML wants [a, b, c, d, 1, 1])
    m = re.fullmatch(r'cubic-bezier\((.*)\)', str(ctx.get('spring', '')))
    if m:
        ctx['spring_points'] = m.group(1)
    alphas = {**cfg.get('opacity', {}), **{k: v for k, v in mode_cfg.items() if isinstance(v, (int, float))}}
    pal = Palette({k: v for k, v in mode_cfg.items() if isinstance(v, str)}, cfg.get('derive', {}), alphas)
    colours = {n: pal.get(n) for n in pal.names()}    # all of them, so a broken formula stops apply early
    return ctx, colours


TOKEN = re.compile(r'\{\{\s*([A-Za-z0-9_]+)(?:\|([a-z0-9]+))?\s*\}\}')


def render(text, ctx, colours, where):
    def sub(m):
        name, how = m.group(1), m.group(2)
        if name in colours:
            return fmt_colour(colours[name], how or 'css')
        if name in ctx:
            return str(ctx[name])
        raise KeyError(f'{where}: "{name}" is not defined by the theme')
    return TOKEN.sub(sub, text)


def path(p):
    return os.path.expanduser(p)


def write_atomic(dest, text):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dest))
    with os.fdopen(fd, 'w') as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, dest)


# ---------- reloads ----------
def sh(*cmd):
    return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def running(name):
    return subprocess.run(['pgrep', '-x', name], stdout=subprocess.DEVNULL).returncode == 0


def reload_apps(changed):
    if 'waybar' in changed and running('waybar'):
        sh('pkill', '-USR2', '-x', 'waybar')
    if 'swaync' in changed and running('swaync'):
        sh('swaync-client', '-rs')
    if 'swayosd' in changed and running('swayosd-server'):
        sh('pkill', '-x', 'swayosd-server')
        subprocess.Popen(['swayosd-server'], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if 'kitty' in changed and running('kitty'):
        sh('pkill', '-USR1', '-x', 'kitty')
    # fuzzel / swaylock read their config each time they start; niri watches its include.


# ---------- commands ----------
def kitty_themes(cfg):
    """Write kitty's dark/light auto-theme files from kitty's own theme collection."""
    k = cfg.get('kitty')
    if not k:
        return False
    out = {}
    for mode in ('dark', 'light'):
        name = k.get(mode)
        if not name:
            continue
        r = subprocess.run(['kitten', 'themes', '--dump-theme', name], capture_output=True, text=True)
        if r.returncode != 0 or not r.stdout.strip():
            print(f'WARNING: kitty theme "{name}" not found (try: kitten themes). Skipping kitty.', file=sys.stderr)
            return False
        out[mode] = r.stdout
    if not out:
        return False
    out['no-preference'] = out[k.get('no_preference', 'dark')] if k.get('no_preference', 'dark') in out else next(iter(out.values()))
    changed = False
    for key, text in out.items():
        dest = path(f'~/.config/kitty/{key}-theme.auto.conf')
        text = (f'# GENERATED by `theme apply` from ~/.config/theme/themes/{cfg["name"]}.toml [kitty]'
                ' - edit that, not this file.\n' + text)
        if not os.path.exists(dest) or open(dest).read() != text:
            write_atomic(dest, text)
            changed = True
    return changed


def gtk_accent(cfg):
    """libadwaita's accent colour (blue, teal, green, yellow, orange, red, pink, purple, slate)."""
    want = cfg.get('gtk', {}).get('accent')
    if want:
        now = subprocess.run(['gsettings', 'get', SCHEMA, 'accent-color'], capture_output=True, text=True).stdout
        if now.strip().strip("'") != want:
            sh('gsettings', 'set', SCHEMA, 'accent-color', want)


# Under niri only, GTK3 apps get the generated GTK3 theme and every GTK app the generated icon theme (themed
# folders). Each lives under two names (Niri, Niri-alt) so that a changed file is picked up live by switching
# name. GNOME resets both at login (~/.config/autostart/gtk-theme-gnome.desktop). GTK_THEME can't be used:
# it makes libadwaita (GTK4) apps drop the accent colour.
SESSION_THEMES = {   # gsettings key: (generated folder, where GTK looks for it, target)
    'gtk-theme': ('~/.config/theme/out/gtk/Niri', '~/.local/share/themes', 'gtk3'),
    'icon-theme': ('~/.config/theme/out/icon-theme/Niri', '~/.local/share/icons', 'folders'),
}


def session_themes(changed):
    for key, (src, where, target) in SESSION_THEMES.items():
        want = path(src)
        for name in ('Niri', 'Niri-alt'):
            link = os.path.join(path(where), name)
            if os.path.isdir(want) and not (os.path.islink(link) and os.readlink(link) == want):
                if os.path.islink(link):
                    os.remove(link)
                if not os.path.exists(link):
                    os.makedirs(os.path.dirname(link), exist_ok=True)
                    os.symlink(want, link)
        if 'NIRI_SOCKET' not in os.environ:      # run from GNOME (or a tty): leave GNOME's themes alone
            continue
        now = subprocess.run(['gsettings', 'get', SCHEMA, key], capture_output=True, text=True).stdout.strip().strip("'")
        if now not in ('Niri', 'Niri-alt'):
            sh('gsettings', 'set', SCHEMA, key, 'Niri')
        elif target in changed:
            sh('gsettings', 'set', SCHEMA, key, 'Niri-alt' if now == 'Niri' else 'Niri')


def apply(mode=None, reload=True, name=None):
    cfg = load(name)
    mode = mode or current_mode()
    ctx, colours = context(cfg, mode)
    rendered = []
    for target, t in cfg['targets'].items():        # render everything first: all or nothing
        src = os.path.join(ROOT, t['src'])
        if os.path.isdir(src):                      # a folder of templates -> a folder of files
            for f in sorted(os.listdir(src)):
                rendered.append((target, os.path.join(path(t['dest']), f),
                                 render(open(os.path.join(src, f)).read(), ctx, colours, os.path.join(t['src'], f))))
        else:
            rendered.append((target, path(t['dest']), render(open(src).read(), ctx, colours, t['src'])))
    if name:                                        # only remember a theme that rendered cleanly
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        with open(STATE, 'w') as f:
            f.write(name + '\n')
    changed = set()
    for target, dest, text in rendered:
        old = open(dest).read() if os.path.exists(dest) else None
        if old != text:
            write_atomic(dest, text)
            changed.add(target)
    if kitty_themes(cfg):
        changed.add('kitty')
    gtk_accent(cfg)
    session_themes(changed)
    if reload:
        reload_apps(changed)
    if changed & {'niri', 'animations'}:
        r = subprocess.run(['niri', 'validate', '-c', path('~/.config/niri/config.kdl')],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print('WARNING: niri rejected the config:\n' + (r.stdout + r.stderr)[-600:], file=sys.stderr)
    print(f'{cfg["name"]} {mode} applied' + (f' ({", ".join(sorted(changed))} updated)' if changed else ' (nothing changed)'))


def set_mode(mode):
    sh('gsettings', 'set', SCHEMA, 'color-scheme', f'prefer-{mode}')
    apply(mode)   # no notification: the quick-settings tile shows the mode


def describe(name):
    try:
        with open(os.path.join(THEMES, name + '.toml'), 'rb') as f:
            return tomllib.load(f).get('description', '')
    except (OSError, tomllib.TOMLDecodeError):
        return ''


def main(argv):
    cmd = argv[1] if len(argv) > 1 else 'status'
    arg = argv[2] if len(argv) > 2 and not argv[2].startswith('-') else None
    if cmd == 'apply':
        apply(reload='--no-reload' not in argv)
    elif cmd == 'toggle':
        set_mode('light' if current_mode() == 'dark' else 'dark')
    elif cmd in ('dark', 'light'):
        set_mode(cmd)
    elif cmd == 'list':
        cur = current_theme()
        for n in themes():
            if '--tsv' in argv:                     # for theme-menu: name <tab> description
                print(f'{n}\t{describe(n)}')
            else:
                print(f'{"*" if n == cur else " "} {n:14} {describe(n)}')
    elif cmd == 'set':
        if not arg:
            print('usage: theme set NAME   (see: theme list)', file=sys.stderr)
            return 1
        apply(name=arg)
    elif cmd in ('next', 'prev'):
        all_, cur = themes(), current_theme()
        i = all_.index(cur) if cur in all_ else 0
        apply(name=all_[(i + (1 if cmd == 'next' else -1)) % len(all_)])
    elif cmd == 'gtk3':                             # niri startup: switch GTK to the generated themes
        session_themes(set())
    elif cmd == 'status':
        print(f'{current_theme()} {current_mode()}')
        if '-v' in argv:
            for target, t in load()['targets'].items():
                print(f'  {t["src"]:28} -> {t["dest"]}')
    elif cmd == 'edit':
        editor = os.environ.get('EDITOR', 'nvim')
        os.execvp(editor, [editor, os.path.join(THEMES, (arg or current_theme()) + '.toml')])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv))
    except (KeyError, ValueError, OSError, tomllib.TOMLDecodeError) as e:
        print(f'theme: {e}', file=sys.stderr)
        sys.exit(1)
