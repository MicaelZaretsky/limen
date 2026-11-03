#!/usr/bin/env python3
"""Put the page together: Fengari and the package's own Lua go inside it, so it needs no server and no CDN.

    python3 web/build.py        writes web/index.html, which works from a folder or from GitHub Pages,
                                and web/fragment.html, the same page without its <html> skeleton
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def read(*parts):
    with open(os.path.join(*parts), encoding='utf8') as f:
        return f.read()


# Fengari builds one arrow function through the Function constructor, which a strict Content-Security-Policy refuses.
# An arrow function written out is the same thing and needs no permission.
fengari = read(HERE, 'vendor', 'fengari-web.js')
GUARD = 'Function("return ()=>void 0;")'
if fengari.count(GUARD) != 1:
    raise SystemExit('Fengari has changed: look at the Function constructor again')
fengari = fengari.replace(GUARD, '(()=>()=>void 0)')
# the replacement character stands in strings of its UTF-8 decoder; an escape means the same and survives any re-encoding
fengari = fengari.replace('\ufffd', '\\ufffd')

page = read(HERE, 'page.html')
notice = read(HERE, 'vendor', 'LICENSE-fengari').replace('*/', '* /')
page = page.replace('/*__FENGARI__*/', '/* Fengari, https://github.com/fengari-lua/fengari-web\n' + notice + '*/\n' + fengari)
for mark, name in (('--__LIMEN_PDF__', 'limen-pdf'), ('--__LIMEN_ART__', 'limen-art'),
                   ('--__LIMEN_PALETTES__', 'limen-palettes'), ('--__LIMEN_SVG__', 'limen-svg')):
    source = read(ROOT, name + '.lua')
    if '</script' in source:
        raise SystemExit(name + ' contains a closing script tag')
    page = page.replace(mark, source)
if '__LIMEN_' in page or '__FENGARI__' in page:
    raise SystemExit('a placeholder is left')
with open(os.path.join(HERE, 'fragment.html'), 'w', encoding='utf8') as f:
    f.write(page)
with open(os.path.join(HERE, 'index.html'), 'w', encoding='utf8') as f:
    f.write('<!doctype html>\n<html lang="ru">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            '</head>\n<body>\n' + page + '\n</body>\n</html>\n')
print(os.path.getsize(os.path.join(HERE, 'index.html')) // 1024, 'KB')
