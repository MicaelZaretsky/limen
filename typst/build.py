#!/usr/bin/env python3
"""Compile a Typst document with limen margins.

    python3 typst/build.py report.typ [--palette ruby] [--beam mono] [--caustic mix] [--seed 3] [--dpi 110] ...

Options after the file name go to limen-svg.lua as they are (see `texlua limen-svg.lua --help`). It needs typst and a Lua
5.3 or later: texlua, lua5.4 or lua. Pages that do not change are not drawn again.

The cycle: compile once and read the marks (headings, thresholds, where the text ends), draw one SVG per page, compile
again with them as page backgrounds. The drawing does not take part in the layout, so one cycle is enough.
"""
import hashlib, json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PT = 2.54 / 72


def find_lua():
    for name in ('texlua', 'lua5.4', 'lua5.3', 'lua'):
        if shutil.which(name):
            return name
    sys.exit('limen: no Lua found: install LuaTeX or Lua 5.3 or later')


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        sys.exit(__doc__)
    doc, extra = sys.argv[1], sys.argv[2:]
    if not shutil.which('typst'):
        sys.exit('limen: typst is not on the PATH')
    base = os.path.splitext(doc)[0]
    workdir = os.path.dirname(os.path.abspath(doc))
    art_dir = 'limen-art'
    art = os.path.join(workdir, art_dir)
    os.makedirs(art, exist_ok=True)

    out = subprocess.run(['typst', 'query', '--root', workdir, doc, '<limen-mark>'], capture_output=True, text=True)
    if out.returncode:
        sys.exit(out.stderr)
    marks = [m['value'] for m in json.loads(out.stdout)]
    sheet = next(m for m in marks if m['kind'] == 'sheet')
    end = next(m for m in marks if m['kind'] == 'textend')
    closing = next((m for m in marks if m['kind'] == 'end'), end)
    pages = end['page']
    H = sheet['height']
    ths = [m for m in marks if m['kind'] == 'threshold']
    textend = H - closing['y'] * PT - 0.8
    u = max(0.45, min(1.4, min(sheet['width'] / 21, H / 29.7)))
    lake = closing['page'] if textend >= 8 * u else 0

    env = dict(os.environ)
    sep = os.pathsep
    env['LUAINPUTS'] = ROOT + sep + env.get('LUAINPUTS', '')
    env['LUA_PATH'] = os.path.join(ROOT, '?.lua') + ';;'
    lua = find_lua()
    common = ['--pages', str(pages), '--width', str(sheet['width']), '--height', str(H)]
    for side in ('left', 'right', 'top', 'bottom'):
        common += ['--' + side, str(sheet[side])]
    if ths:
        common += ['--ths', ','.join(f"{t['page']}:{t['y'] * PT / H:.4f}" for t in ths)]
    common += extra
    drawn = 0
    for page in range(1, pages + 1):
        here = []
        for m in marks:
            if m.get('page') != page:
                continue
            y = H - m['y'] * PT
            if m['kind'] == 'heading':
                here.append(f"heading:{y - 0.4:.3f}:{m['arg']}")
            elif m['kind'] == 'star':
                here.append(f"star:{y - 0.3:.3f}")
            elif m['kind'] == 'threshold':
                here.append(f"threshold:{y - 0.3:.3f}")
            elif m['kind'] == 'caustic':
                here.append(f"caustic:{y:.3f}:{m['arg']}")
        args = common + ['--page', str(page)]
        if here:
            args += ['--marks', ','.join(here)]
        if page == closing['page']:
            args += ['--closing', 'yes', '--textend', f'{textend:.3f}']
        else:
            args += ['--closing', 'no']
        key = hashlib.sha256(' '.join(args).encode()).hexdigest()[:16]
        svg, stamp = os.path.join(art, f'page-{page}.svg'), os.path.join(art, f'page-{page}.key')
        if os.path.exists(svg) and os.path.exists(stamp) and open(stamp).read() == key:
            continue
        with open(svg, 'w') as f:
            done = subprocess.run([lua, os.path.join(ROOT, 'limen-svg.lua')] + args, stdout=f, env=env)
        if done.returncode:
            sys.exit(f'limen: drawing page {page} failed')
        open(stamp, 'w').write(key)
        drawn += 1
    print(f'limen: {pages} page(s), {drawn} drawn, closing on page {closing["page"]}' + (' with the field below the text' if lake else ''))
    # image paths in Typst are relative to the file that names them unless they start at the project root
    done = subprocess.run(['typst', 'compile', '--root', workdir, '--input', f'limen-art=/{art_dir}', '--input', f'limen-lake={lake}', doc, base + '.pdf'])
    sys.exit(done.returncode)


if __name__ == '__main__':
    main()
