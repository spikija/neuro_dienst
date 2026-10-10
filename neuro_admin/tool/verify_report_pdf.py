"""Optional independent inspection after report_pdf_test.dart (PyMuPDF needed).

Run from neuro_admin: python tool/verify_report_pdf.py
Only synthetic test PDFs in build/test-pdf are opened; no backend is contacted.
"""
from pathlib import Path
import fitz


for name in ("portrait", "landscape", "physicians"):
    with fitz.open(Path("build/test-pdf") / f"{name}.pdf") as document:
        text = "\n".join(page.get_text() for page in document)
        for page in document:
            assert "Datum" in page.get_text(), "Missing repeated header"
            assert "Seite" in page.get_text(), "Missing page number"
            width, height = (841.89, 595.28) if name == "landscape" else (595.28, 841.89)
            assert abs(page.rect.width - width) < 1
            assert abs(page.rect.height - height) < 1
            for block in page.get_text("blocks"):
                assert 0 <= block[0] <= block[2] <= page.rect.width + 1
                assert 0 <= block[1] <= block[3] <= page.rect.height + 1
        if name == "physicians":
            assert "Ana Example" in text, "Inactive historical physician omitted"
        else:
            for index in range(18):
                assert f"Report role {index}" in text, "Report column dropped"
            assert "Abwesenheiten / Feiertag" in text, "Final column dropped"
        print(f"{name}: {len(document)} pages; A4, headers, bounds and columns verified")
