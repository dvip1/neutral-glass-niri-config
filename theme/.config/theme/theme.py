#!/usr/bin/env python3
"""Central theme engine.  See ~/.config/theme/README.md.

  theme apply          render every template from theme.toml and reload the apps
  theme toggle         flip dark <-> light
  theme dark | light   set a mode
  theme status         show the current mode and what gets generated
  theme edit           open theme.toml in $EDITOR
"""
import os
import re
import subprocess
import sys
import tempfile
import tomllib

ROOT = os.path.dirname(os.path.realpath(__file__))
CONF = os.path.join(ROOT, 'theme.toml')
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
    if how == 'hash8':    # #rrggbbaa  (niri)
        return f'#{r:02x}{g:02x}{b:02x}{a8:02x}'
    raise ValueError(f'unknown colour filter: {how}')


# ---------- state ----------
def current_mode():
    out = subprocess.run(['gsettings', 'get', SCHEMA, 'color-scheme'], capture_output=True, text=True).stdout
    return 'dark' if 'prefer-dark' in out else 'light'


def load():
    with open(CONF, 'rb') as f:
        return tomllib.load(f)


def context(cfg, mode):
    ctx = {
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
    }
    colours = {k: parse_colour(v) for k, v in cfg[mode].items()}
    return ctx, colours


TOKEN = re.compile(r'\{\{\s*([A-Za-z0-9_]+)(?:\|([a-z0-9]+))?\s*\}\}')


def render(text, ctx, colours, where):
    def sub(m):
        name, how = m.group(1), m.group(2)
        if name in colours:
            return fmt_colour(colours[name], how or 'css')
        if name in ctx:
            return str(ctx[name])
        raise KeyError(f'{where}: "{name}" is not defined in theme.toml')
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
        text = '# GENERATED by `theme apply` from ~/.config/theme/theme.toml [kitty] - edit that, not this file.\n' + text
        if not os.path.exists(dest) or open(dest).read() != text:
            write_atomic(dest, text)
            changed = True
    return changed


def apply(mode=None, reload=True):
    cfg = load()
    mode = mode or current_mode()
    ctx, colours = context(cfg, mode)
    rendered = []
    for name, t in cfg['targets'].items():          # render everything first: all or nothing
        src = os.path.join(ROOT, t['src'])
        if os.path.isdir(src):                      # a folder of templates -> a folder of files
            for f in sorted(os.listdir(src)):
                rendered.append((name, os.path.join(path(t['dest']), f),
                                 render(open(os.path.join(src, f)).read(), ctx, colours, os.path.join(t['src'], f))))
        else:
            rendered.append((name, path(t['dest']), render(open(src).read(), ctx, colours, t['src'])))
    changed = set()
    for name, dest, text in rendered:
        old = open(dest).read() if os.path.exists(dest) else None
        if old != text:
            write_atomic(dest, text)
            changed.add(name)
    if kitty_themes(cfg):
        changed.add('kitty')
    if reload:
        reload_apps(changed)
    if 'niri' in changed:
        r = subprocess.run(['niri', 'validate', '-c', path('~/.config/niri/config.kdl')],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print('WARNING: niri rejected the config:\n' + (r.stdout + r.stderr)[-600:], file=sys.stderr)
    print(f'{mode} theme applied' + (f' ({", ".join(sorted(changed))} updated)' if changed else ' (nothing changed)'))


def set_mode(mode):
    sh('gsettings', 'set', SCHEMA, 'color-scheme', f'prefer-{mode}')
    apply(mode)
    sh('notify-send', '-a', 'theme', f'{mode.capitalize()} mode', f'Switched to {mode} glass')


def main(argv):
    cmd = argv[1] if len(argv) > 1 else 'status'
    if cmd == 'apply':
        apply(reload='--no-reload' not in argv)
    elif cmd == 'toggle':
        set_mode('light' if current_mode() == 'dark' else 'dark')
    elif cmd in ('dark', 'light'):
        set_mode(cmd)
    elif cmd == 'status':
        print(current_mode())
        if '-v' in argv:
            for name, t in load()['targets'].items():
                print(f'  {t["src"]:28} -> {t["dest"]}')
    elif cmd == 'edit':
        os.execvp(os.environ.get('EDITOR', 'nvim'), [os.environ.get('EDITOR', 'nvim'), CONF])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv))
    except (KeyError, ValueError, OSError) as e:
        print(f'theme: {e}', file=sys.stderr)
        sys.exit(1)
