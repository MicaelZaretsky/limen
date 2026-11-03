#!/usr/bin/env python3
"""Compare PDF renderers page by page: a blended mesh or a broken resource shows up as a large difference.

    PDFIUM_LIB=/path/to/libpdfium.so PDFJS_DIST=/path/to/pdfjs-dist python3 tools/crosscheck.py a.pdf b.pdf ...

Poppler is the reference; PDFium and pdf.js are used when their paths are set. For each file and renderer it
prints the worst page and the mean absolute difference (0..100 %) after shrinking pages to a quarter of their
size. Shrinking removes what renderers legitimately do differently, glyph antialiasing and how they treat
hairlines. What remains is colour, which is what goes wrong when a mesh does. The exit status is 1 above 6 %.
"""
import glob, os, subprocess, sys, tempfile
from PIL import Image, ImageChops, ImageStat

here = os.path.dirname(os.path.abspath(__file__))


def others(pdf, t):
    if os.environ.get('PDFIUM_LIB'):
        subprocess.run([sys.executable, '-I', os.path.join(here, 'render-pdfium.py'), pdf, t, '72'],
                       check=True, stdout=subprocess.DEVNULL)
        yield 'PDFium', sorted(glob.glob(t + '/pf-*.png'))
    if os.environ.get('PDFJS_DIST'):
        subprocess.run(['node', os.path.join(here, 'render-pdfjs.js'), pdf, t, '1'], check=True, stdout=subprocess.DEVNULL)
        yield 'pdf.js', sorted(glob.glob(t + '/js-*.png'))


status = 0
for pdf in sys.argv[1:]:
    t = tempfile.mkdtemp()
    subprocess.run(['pdftoppm', '-r', '72', '-png', pdf, t + '/po'], check=True, stderr=subprocess.DEVNULL)
    po = sorted(glob.glob(t + '/po-*.png'))
    for name, pages in others(pdf, t):
        if len(pages) != len(po):
            print(f'{os.path.basename(pdf):26s} {name:7s} page counts differ: {len(po)} and {len(pages)}')
            status = 1
            continue
        worst, wp = 0, 0
        for i, (a, b) in enumerate(zip(po, pages), 1):
            A, B = Image.open(a).convert('RGB'), Image.open(b).convert('RGB')
            if A.size != B.size:
                B = B.resize(A.size)
            small = (A.width // 4, A.height // 4)
            d = sum(ImageStat.Stat(ImageChops.difference(A.resize(small, Image.BOX), B.resize(small, Image.BOX))).mean) / 3 / 255 * 100
            if d > worst:
                worst, wp = d, i
        print(f'{os.path.basename(pdf):26s} {name:7s} pages {len(po):3d}   worst page {wp:3d}: {worst:5.2f} %')
        if worst > 6:
            status = 1
sys.exit(status)
