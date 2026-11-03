#!/usr/bin/env python3
"""Check that limen-svg.lua draws what LuaLaTeX draws: python3 tools/svgcheck.py

Builds a document with empty pages, draws the same pages with limen-svg.lua, renders both and prints the mean absolute
difference. Needs lualatex, texlua, pdftoppm, Pillow and the playwright module with Chromium. The exit status is 1 above 1.5 %.
"""
import base64, os, subprocess, sys, tempfile
from PIL import Image, ImageChops, ImageStat
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
t = tempfile.mkdtemp(prefix='limen-svgcheck-')
env = dict(os.environ)
env['TEXINPUTS'] = ROOT + os.pathsep + env.get('TEXINPUTS', '')
env['LUAINPUTS'] = ROOT + os.pathsep + env.get('LUAINPUTS', '')
open(os.path.join(t, 'd.tex'), 'w').write(r'''\documentclass[10pt,a4paper]{article}
\usepackage[left=58mm,right=17mm,top=30mm,bottom=29mm,headsep=8mm]{geometry}
\usepackage[finale=false]{limen}
\pagestyle{empty}
\begin{document}
\null\clearpage\null\clearpage\null\clearpage\null\clearpage\null\clearpage\null\clearpage
\end{document}
''')
for _ in range(2):
    subprocess.run(['lualatex', '-interaction=nonstopmode', '-halt-on-error', 'd.tex'], cwd=t, env=env, check=True, stdout=subprocess.DEVNULL)
worst = 0
with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={'width': 595, 'height': 842})
    for n in (1, 3, 6):
        svg = subprocess.run(['texlua', os.path.join(ROOT, 'limen-svg.lua'), '--page', str(n), '--pages', '6', '--finale', 'no', '--dpi', '150'],
                             env=env, check=True, stdout=subprocess.PIPE).stdout
        data = base64.b64encode(svg).decode()
        page.set_content(f'<!doctype html><body style="margin:0;background:#fff"><img id=i style="width:595px;height:842px;display:block" src="data:image/svg+xml;base64,{data}"></body>')
        page.wait_for_function("document.getElementById('i').complete")
        a = os.path.join(t, f's{n}.png')
        page.screenshot(path=a)
        subprocess.run(['pdftoppm', '-r', '72', '-f', str(n), '-l', str(n), '-singlefile', '-png', 'd.pdf', f'p{n}'], cwd=t, check=True, stderr=subprocess.DEVNULL)
        A, B = Image.open(a).convert('RGB'), Image.open(os.path.join(t, f'p{n}.png')).convert('RGB').resize((595, 842))
        small = (148, 210)
        d = sum(ImageStat.Stat(ImageChops.difference(A.resize(small, Image.BOX), B.resize(small, Image.BOX))).mean) / 3 / 255 * 100
        print(f'page {n}: {d:.2f} %')
        worst = max(worst, d)
    b.close()
sys.exit(1 if worst > 1.5 else 0)
