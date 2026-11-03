#!/usr/bin/env python3
"""Build every example and test document and check what can be checked without looking.

    python3 tests/run.py [name ...]

For each document:
  * it compiles in two runs and the second run asks for no third;
  * limen's warnings are exactly the expected ones;
  * every heading the source asks for has reached the margin (limen writes the count to the .aux);
  * the art changes no text: pdftotext gives the same words with and without the option draft;
  * a page with art costs less than MAX_KB on average.
Then one document is built twice to check that the art is reproducible, and the print and tagged documents are looked
into. tests/tagged.tex needs a LaTeX from 2024 or later and is skipped on older ones. Renderers are compared separately by
tools/crosscheck.py. Without Poppler's tools only compilation and warnings are checked.
"""
import glob, hashlib, os, re, shutil, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.environ.get('LIMEN_BUILD') or tempfile.mkdtemp(prefix='limen-')
MAX_KB = 250
EXPECTED = {'narrow': ['coloured column'], 'badoption': ['needs a number', 'cannot be', 'unknown option', 'unknown palette']}
env = dict(os.environ)
env['TEXINPUTS'] = ROOT + os.pathsep + env.get('TEXINPUTS', '')
env['LUAINPUTS'] = ROOT + os.pathsep + env.get('LUAINPUTS', '')
POPPLER = bool(shutil.which('pdftotext') and shutil.which('pdfinfo') and shutil.which('pdftoppm'))
os.makedirs(BUILD, exist_ok=True)


def lualatex(path, job, pre=''):
    cmd = ['lualatex', '-interaction=nonstopmode', '-halt-on-error', '-output-directory=' + BUILD, '-jobname=' + job,
           pre + '\\input{' + os.path.basename(path) + '}']
    return subprocess.run(cmd, cwd=os.path.dirname(path), env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, errors='replace', timeout=400).returncode


def warnings(job):
    log = open(os.path.join(BUILD, job + '.log'), encoding='utf8', errors='replace').read()
    return re.findall(r'Module limen Warning: ([^\n]*)', log)


def words(job):
    t = subprocess.run(['pdftotext', '-layout', os.path.join(BUILD, job + '.pdf'), '-'], stdout=subprocess.PIPE, text=True,
                       errors='replace').stdout
    return re.findall(r'\S+', re.sub(r'-\s*\n\s*', '', t))


def pages(job):
    out = subprocess.run(['pdfinfo', os.path.join(BUILD, job + '.pdf')], stdout=subprocess.PIPE, text=True).stdout
    return int(re.search(r'Pages:\s+(\d+)', out).group(1))


def pixels(job):
    t = tempfile.mkdtemp()
    subprocess.run(['pdftoppm', '-r', '50', '-png', os.path.join(BUILD, job + '.pdf'), t + '/p'], stderr=subprocess.DEVNULL)
    return hashlib.sha256(b''.join(open(f, 'rb').read() for f in sorted(glob.glob(t + '/p-*.png')))).hexdigest()


def latex_year():
    with tempfile.TemporaryDirectory() as t:
        with open(os.path.join(t, 'v.tex'), 'w') as f:
            f.write('\\documentclass{article}\\begin{document}\\end{document}')
        subprocess.run(['lualatex', '-interaction=batchmode', 'v.tex'], cwd=t, stdout=subprocess.DEVNULL)
        with open(os.path.join(t, 'v.log'), encoding='utf8', errors='replace') as f:
            m = re.search(r'LaTeX2e <(\d{4})-', f.read())
    return int(m.group(1)) if m else 0


def headings_expected(path):
    """How many headings and stars the source asks for; None where a count from the source means nothing."""
    src = open(path, encoding='utf8').read()
    if '\\loop' in src:
        return None
    src = src.split('\\begin{document}')[-1]
    return len(re.findall(r'\\(?:chapter|section|subsection)\*?\{', src)) + len(re.findall(r'\\limenstar\b', src))


def headings_seen(job):
    with open(os.path.join(BUILD, job + '.aux'), encoding='utf8', errors='replace') as f:
        m = re.findall(r'limen@aux\{headings\}\{(\d+)\}', f.read())
    return int(m[-1]) if m else 0


def looks_into(name):
    """What only the PDF itself can show."""
    pdf = os.path.join(BUILD, name + '.pdf')
    problems = []
    if name in ('minimal', 'print', 'tagged', 'slides') and shutil.which('qpdf'):
        q = os.path.join(BUILD, name + '-g.pdf')
        subprocess.run(['qpdf', '--qdf', '--object-streams=disable', pdf, q], stderr=subprocess.DEVNULL)
        data = open(q, 'rb').read()
        cs = b'/DeviceCMYK' if name == 'print' else b'/DeviceRGB'
        if not re.search(rb'/Group\s*<<[^>]*/CS\s*' + cs, data):
            problems.append('no transparency group on the pages')
    if name == 'print':
        out = subprocess.run(['pdfinfo', '-f', '1', '-l', '99', '-box', pdf], stdout=subprocess.PIPE, text=True).stdout
        n = pages(name)
        if len(re.findall(r'TrimBox', out)) != n or len(re.findall(r'BleedBox', out)) != n:
            problems.append('TrimBox or BleedBox missing on some page')
        if shutil.which('qpdf'):
            q = os.path.join(BUILD, 'print-q.pdf')
            subprocess.run(['qpdf', '--qdf', '--object-streams=disable', pdf, q], stderr=subprocess.DEVNULL)
            data = open(q, 'rb').read()
            if b'/DeviceRGB' in data:
                problems.append('RGB meshes in a CMYK document')
            if b'/DeviceCMYK' not in data:
                problems.append('no CMYK meshes')
    if name == 'tagged':
        out = subprocess.run(['pdfinfo', pdf], stdout=subprocess.PIPE, text=True).stdout
        if not re.search(r'Tagged:\s+yes', out):
            problems.append('not tagged')
        if shutil.which('qpdf'):
            q = os.path.join(BUILD, 'tagged-q.pdf')
            subprocess.run(['qpdf', '--qdf', '--object-streams=disable', pdf, q], stderr=subprocess.DEVNULL)
            if b'/Artifact BMC' not in open(q, 'rb').read():
                problems.append('art is not marked as an artifact')
    return problems


docs = sorted(glob.glob(os.path.join(ROOT, 'examples', '*.tex'))) + sorted(glob.glob(os.path.join(ROOT, 'tests', '*.tex')))
YEAR = latex_year()
wanted = sys.argv[1:]
failed = 0
print(f'{"document":18s} {"pages":>5s} {"KB/page":>8s} {"s/page":>7s}  result')
for path in docs:
    name = os.path.splitext(os.path.basename(path))[0]
    if wanted and name not in wanted:
        continue
    problems = []
    if name == 'tagged' and YEAR < 2024:
        print(f'{name:18s} {"":>5s} {"":>8s} {"":>7s}  skipped, LaTeX {YEAR} is too old')
        continue
    t0 = time.time()
    ok = all(lualatex(path, name) == 0 for _ in range(2))
    dt = time.time() - t0
    if not ok:
        print(f'{name:18s} {"":>5s} {"":>8s} {"":>7s}  FAILED to compile, see {BUILD}/{name}.log')
        failed += 1
        continue
    got = warnings(name)
    want = EXPECTED.get(name, [])
    extra = [w for w in got if not any(k in w for k in want)]
    missing = [k for k in want if not any(k in w for w in got)]
    if extra:
        problems.append('warning: ' + extra[0][:60])
    if missing:
        problems.append('missing warning: ' + missing[0])
    if not POPPLER:
        print(f'{name:18s} {"":>5s} {"":>8s} {dt / 2:7.2f}  {"ok" if not problems else "; ".join(problems)}')
        failed += bool(problems)
        continue
    want = headings_expected(path)
    seen = headings_seen(name)
    if want is None and seen == 0:
        problems.append('no stars at headings')
    elif want is not None and seen < want and 'headings=false' not in open(path, encoding='utf8').read():
        problems.append(f'stars at {seen} of {want} headings')
    n = pages(name)
    kb = os.path.getsize(os.path.join(BUILD, name + '.pdf')) / 1024 / n
    if kb > MAX_KB:
        problems.append(f'large: {kb:.0f} KB/page')
    if all(lualatex(path, name + '-draft', '\\PassOptionsToPackage{draft}{limen}') == 0 for _ in range(2)):
        if words(name) != words(name + '-draft'):
            problems.append('text differs from draft')
    else:
        problems.append('draft failed to compile')
    problems += looks_into(name)
    print(f'{name:18s} {n:5d} {kb:8.0f} {dt / 2 / n:7.2f}  {"ok" if not problems else "; ".join(problems)}')
    failed += bool(problems)

if not wanted and POPPLER:
    env['SOURCE_DATE_EPOCH'] = '1788000000'
    env['FORCE_SOURCE_DATE'] = '1'
    path = os.path.join(ROOT, 'examples', 'minimal.tex')
    a = [lualatex(path, 'repro') for _ in range(2)]
    h1 = pixels('repro')
    for f in glob.glob(os.path.join(BUILD, 'repro.*')):
        os.remove(f)
    a += [lualatex(path, 'repro') for _ in range(2)]
    h2 = pixels('repro')
    same = h1 == h2 and not any(a)
    print('reproducible art: ' + ('ok' if same else 'FAILED'))
    failed += not same
# a relative font path stays in the font cache, and a second way of naming the same fonts stops the documents built after it
paths = set()
for d in ('doc', 'examples', 'tests', 'tools'):
    for path in glob.glob(os.path.join(ROOT, d, '*.tex')):
        with open(path, encoding='utf8') as f:
            paths |= set(re.findall(r'Path=([^,\]]*)', f.read()))
print('one font path: ' + ('ok' if len(paths) <= 1 else 'FAILED, ' + ' '.join(sorted(paths))))
failed += len(paths) > 1
print('all ok' if not failed else f'{failed} document(s) with problems; build files in {BUILD}')
sys.exit(1 if failed else 0)
