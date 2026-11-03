#!/usr/bin/env python3
"""Rebuild the pictures in gallery/ from the examples: python3 tools/gallery.py

Needs lualatex, pdftoppm and Pillow.
"""
import glob, os, subprocess, tempfile
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EX = os.path.join(ROOT, 'examples')
OUT = os.path.join(ROOT, 'gallery')
BUILD = tempfile.mkdtemp(prefix='limen-gallery-')
os.makedirs(OUT, exist_ok=True)
env = dict(os.environ)
env['TEXINPUTS'] = ROOT + ':' + env.get('TEXINPUTS', '')
env['LUAINPUTS'] = ROOT + ':' + env.get('LUAINPUTS', '')
BG = (243, 243, 246)


def build(name, job=None, pre=''):
    job = job or name
    for _ in range(2):
        subprocess.run(['lualatex', '-interaction=nonstopmode', '-halt-on-error', '-output-directory=' + BUILD,
                        '-jobname=' + job, pre + '\\input{' + name + '.tex}'], cwd=EX, env=env, check=True,
                       stdout=subprocess.DEVNULL)
    return os.path.join(BUILD, job + '.pdf')


def render(pdf, dpi, pages=None):
    """Poppler spends a second or two per page on the meshes, so only the pages that are needed."""
    out = []
    for p in pages or [None]:
        t = tempfile.mkdtemp()
        cmd = ['pdftoppm', '-r', str(dpi), '-png'] + (['-f', str(p), '-l', str(p)] if p else []) + [pdf, t + '/p']
        subprocess.run(cmd, check=True, stderr=subprocess.DEVNULL)
        out += [Image.open(f).convert('RGB') for f in sorted(glob.glob(t + '/p-*.png'))]
    return out


def row(images, gap=14, pad=14):
    w = sum(i.width for i in images) + gap * (len(images) - 1) + 2 * pad
    h = max(i.height for i in images) + 2 * pad
    s = Image.new('RGB', (w, h), BG)
    x = pad
    for i in images:
        s.paste(i, (x, pad))
        x += i.width + gap
    return s


def save(im, name):
    im.convert('P', palette=Image.ADAPTIVE, colors=255).save(os.path.join(OUT, name), optimize=True)
    print(name, im.size, os.path.getsize(os.path.join(OUT, name)) // 1024, 'KB')


spec = build('specimen')
save(row(render(spec, 72, [1, 4, 8])), 'hero.png')
save(row([i.crop((0, 0, int(i.width * 0.27), i.height)) for i in render(spec, 62)], gap=6), 'story.png')
last = []
for pal in ['ultramarine', 'peacock', 'ruby', 'emerald', 'infrared', 'graphite']:
    last += render(build('specimen', 'sp-' + pal, '\\def\\specimenopts{palette=' + pal + '}'), 42, [8])
save(row(last, gap=8), 'palettes.png')
save(row(render(build('specimen', 'sp-paper', '\\def\\specimenopts{mode=paper}'), 60, [1, 4, 8])), 'paper.png')
save(row(render(build('cover'), 60, [1, 2])), 'cover.png')
save(row(render(build('slides'), 80, [1, 2, 8]), gap=10), 'slides.png')
t = render(build('twoside'), 60, [2, 3])
spread = Image.new('RGB', (t[0].width + t[1].width, t[0].height), BG)
spread.paste(t[0], (0, 0))
spread.paste(t[1], (t[0].width, 0))
save(row([spread]), 'twoside.png')

TESTS = os.path.join(ROOT, 'tests')


def build_test(name):
    for _ in range(2):
        subprocess.run(['lualatex', '-interaction=nonstopmode', '-halt-on-error', '-output-directory=' + BUILD,
                        name + '.tex'], cwd=TESTS, env=env, check=True, stdout=subprocess.DEVNULL)
    return os.path.join(BUILD, name + '.pdf')


c = render(build_test('caustics'), 76, [1])[0]
save(row([c.crop((0, 0, int(c.width * 0.27), c.height))]), 'caustics.png')
save(row(render(build_test('mono'), 60, [1, 2, 4])), 'mono.png')

# how much darker than white the pages are: a rough measure of ink, night against paper
from PIL import ImageStat


def darkness(pdf):
    v = [100 - ImageStat.Stat(i.convert('L')).mean[0] / 255 * 100 for i in render(pdf, 40)]
    return sum(v) / len(v)


night, paper = darkness(spec), darkness(os.path.join(BUILD, 'sp-paper.pdf'))
print(f'mean darkness of a page: night {night:.1f} %, paper {paper:.1f} %, ratio {night / paper:.1f}')
