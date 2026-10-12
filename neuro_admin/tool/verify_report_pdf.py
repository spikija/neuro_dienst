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
            assert len(document) == 1, "Standard monthly roster must fit one page"
            normalized = " ".join(text.split())
            compact = "".join(text.split())
            for label in ["Science Slot", "Stroke Unit Leader", "Stroke Unit Team 1", "Stroke Unit Team 2", "Ambulance", "Neurosonology", "Neurovascular Interdisciplinary Board", "OFO Board", "Other clinic"]:
                assert "".join(label.split()) in compact, f"Report column dropped: {label}"
            page = document[0]
            top = lambda date: page.search_for(date)[0].y0
            assert top("05.10.2026")-top("04.10.2026") < top("06.10.2026")-top("05.10.2026"), "Empty weekend row is not shorter"
            assert "Nationalfeiertag" in text, "Holiday annotation missing"
            assert "05.10.2026" in text
            assert "2026-10-05" not in text
            spans = [span for page in document for block in page.get_text("dict")["blocks"]
                     if "lines" in block for line in block["lines"] for span in line["spans"]]
            weekday_spans = [span for span in spans if span["text"].strip() in {"Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"}]
            assert len(weekday_spans) == 31
            assert all(span["flags"] & 16 for span in weekday_spans), "Weekday must be bold"
            colors = [drawing["fill"] for page in document for drawing in page.get_drawings() if drawing["fill"]]
            assert len(set(colors)) >= 4, "Header/weekend/holiday hierarchy missing"
            assert "Abwesenheiten / Feiertag" in " ".join(text.split()), "Final column dropped"
        print(f"{name}: {len(document)} pages; A4, headers, bounds and columns verified")

for orientation in ("portrait", "landscape"):
    with fitz.open(Path("build/test-pdf") / f"selected-{orientation}.pdf") as document:
        assert len(document) == 1
        text = " ".join(document[0].get_text().split())
        assert "Custom Clinic" in text and "Hidden Default" in text
        assert "Rare Board" not in text and "RARE" not in text
        assert text.index("Custom Clinic") < text.index("Hidden Default")
        assert (document[0].rect.width > document[0].rect.height) == (orientation == "landscape")
        for block in document[0].get_text("blocks"):
            assert 0 <= block[0] <= block[2] <= document[0].rect.width + 1
        print(f"selected-{orientation}: selected columns present, unselected role absent, configured order and bounds verified")
