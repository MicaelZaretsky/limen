#!/usr/bin/env python3
"""Render every page through PDFium, the engine of Chrome and Edge.

    PDFIUM_LIB=/path/to/libpdfium.so python3 tools/render-pdfium.py in.pdf outdir [dpi]

A prebuilt library: https://github.com/bblanchon/pdfium-binaries
"""
import ctypes as C, sys, os
from PIL import Image
lib = C.CDLL(os.environ.get('PDFIUM_LIB', 'libpdfium.so'))
lib.FPDF_InitLibrary.restype = None; lib.FPDF_InitLibrary()
lib.FPDF_LoadDocument.restype = C.c_void_p; lib.FPDF_LoadDocument.argtypes = [C.c_char_p, C.c_char_p]
lib.FPDF_GetPageCount.argtypes = [C.c_void_p]
lib.FPDF_LoadPage.restype = C.c_void_p; lib.FPDF_LoadPage.argtypes = [C.c_void_p, C.c_int]
lib.FPDF_GetPageWidth.restype = C.c_double; lib.FPDF_GetPageWidth.argtypes = [C.c_void_p]
lib.FPDF_GetPageHeight.restype = C.c_double; lib.FPDF_GetPageHeight.argtypes = [C.c_void_p]
lib.FPDFBitmap_Create.restype = C.c_void_p; lib.FPDFBitmap_Create.argtypes = [C.c_int, C.c_int, C.c_int]
lib.FPDFBitmap_FillRect.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_int, C.c_ulong]
lib.FPDFBitmap_GetBuffer.restype = C.c_void_p; lib.FPDFBitmap_GetBuffer.argtypes = [C.c_void_p]
lib.FPDFBitmap_GetStride.argtypes = [C.c_void_p]
lib.FPDF_RenderPageBitmap.argtypes = [C.c_void_p, C.c_void_p] + [C.c_int] * 6
pdf, out, dpi = sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 72
os.makedirs(out, exist_ok=True)
d = lib.FPDF_LoadDocument(pdf.encode(), None)
n = lib.FPDF_GetPageCount(d)
for i in range(n):
    p = lib.FPDF_LoadPage(d, i)
    w, h = round(lib.FPDF_GetPageWidth(p) * dpi / 72), round(lib.FPDF_GetPageHeight(p) * dpi / 72)
    b = lib.FPDFBitmap_Create(w, h, 1)
    lib.FPDFBitmap_FillRect(b, 0, 0, w, h, 0xFFFFFFFF)
    lib.FPDF_RenderPageBitmap(b, p, 0, 0, w, h, 0, 0)
    buf = C.string_at(lib.FPDFBitmap_GetBuffer(b), lib.FPDFBitmap_GetStride(b) * h)
    Image.frombuffer('RGBA', (w, h), buf, 'raw', 'BGRA', lib.FPDFBitmap_GetStride(b), 1).convert('RGB').save(f'{out}/pf-{i+1:03d}.png')
print(n)
