#!/usr/bin/env python3
"""Make gallery/growth.gif, the story of one page from below the threshold to the full spectrum.

    python3 tools/animate.py [frames]

One document with one page per frame: the same picture (sameart) at rising stages (\\limenlevel). Needs lualatex, pdftoppm
and Pillow. Poppler spends a second or two per page on the meshes, so this takes about a minute.
"""
import glob, os, subprocess, sys, tempfile
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = int(sys.argv[1]) if len(sys.argv) > 1 else 24
t = tempfile.mkdtemp(prefix='limen-anim-')
env = dict(os.environ)
env['TEXINPUTS'] = ROOT + os.pathsep + env.get('TEXINPUTS', '')
env['LUAINPUTS'] = ROOT + os.pathsep + env.get('LUAINPUTS', '')
frames = []
for k in range(N):
    frames.append('\\limenlevel{%.3f}\n\\setcounter{section}{0}\n\\section{Below the threshold}\\lipsum[1-3]\n\\section{Above it}\\lipsum[4-6]\n\\clearpage\n' % (k / (N - 1)))
open(os.path.join(t, 'a.tex'), 'w').write('''\\documentclass[10pt,a4paper]{article}
\\usepackage[left=58mm,right=17mm,top=30mm,bottom=29mm]{geometry}
\\usepackage{lipsum}
\\usepackage[finale=false,sameart=true,seed=4]{limen}
\\pagestyle{empty}
\\begin{document}
''' + ''.join(frames) + '\\end{document}\n')
for _ in range(2):
    subprocess.run(['lualatex', '-interaction=nonstopmode', '-halt-on-error', 'a.tex'], cwd=t, env=env, check=True, stdout=subprocess.DEVNULL)
subprocess.run(['pdftoppm', '-r', '50', '-png', 'a.pdf', 'f'], cwd=t, check=True, stderr=subprocess.DEVNULL)
ims = [Image.open(f).convert('RGB') for f in sorted(glob.glob(t + '/f-*.png'))]
w, h = ims[0].size
ims = [i.crop((0, 0, int(w * 0.62), h)) for i in ims]
pal = ims[-1].quantize(colors=250, method=Image.MEDIANCUT, dither=Image.NONE)
out = [i.quantize(palette=pal, dither=Image.NONE) for i in ims]
path = os.path.join(ROOT, 'gallery', 'growth.gif')
out[0].save(path, save_all=True, append_images=out[1:], duration=[900] + [130] * (N - 2) + [1800], loop=0, optimize=True)
print(path, len(out), 'frames,', os.path.getsize(path) // 1024, 'KB')
