// Render every page of a PDF through pdf.js in Chromium, as a second opinion next to Poppler.
//   PDFJS_DIST=/path/to/pdfjs-dist node tools/render-pdfjs.js in.pdf outdir [scale]
// Needs the playwright module and a clone of https://github.com/mozilla/pdfjs-dist.
const {chromium} = require('playwright'); const fs = require('fs'), path = require('path');
(async () => {
  const [,, inp, out, sc = '1'] = process.argv;
  const lib = path.join(process.env.PDFJS_DIST || 'pdfjs-dist', 'build');
  fs.mkdirSync(out, {recursive: true});
  const b = await chromium.launch(); const p = await b.newPage({viewport: {width: 1600, height: 2200}});
  await p.setContent('<canvas id=c></canvas>');
  await p.addScriptTag({path: path.join(lib, 'pdf.min.js')});
  const data = fs.readFileSync(inp).toString('base64');
  const worker = fs.readFileSync(path.join(lib, 'pdf.worker.min.js'), 'utf8');
  const n = await p.evaluate(async ({data, worker}) => {
    const L = window.pdfjsLib || window['pdfjs-dist/build/pdf'];
    L.GlobalWorkerOptions.workerSrc = URL.createObjectURL(new Blob([worker], {type: 'text/javascript'}));
    const bin = Uint8Array.from(atob(data), c => c.charCodeAt(0));
    window.doc = await L.getDocument({data: bin}).promise; return window.doc.numPages;
  }, {data, worker});
  for (let i = 1; i <= n; i++) {
    const url = await p.evaluate(async ({i, sc}) => {
      const page = await window.doc.getPage(i); const v = page.getViewport({scale: +sc});
      const c = document.getElementById('c'); c.width = v.width; c.height = v.height;
      await page.render({canvasContext: c.getContext('2d'), viewport: v}).promise; return c.toDataURL('image/png');
    }, {i, sc});
    fs.writeFileSync(path.join(out, `js-${String(i).padStart(3, '0')}.png`), Buffer.from(url.split(',')[1], 'base64'));
  }
  console.log(n); await b.close();
})().catch(e => { console.error(e); process.exit(1); });
