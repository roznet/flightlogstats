"""Render a reconciliation to a PDF (tables + embedded route map).

Reuses the markdown produced by ``report.markdown`` and turns its blocks
(headings, paragraphs, tables) into reportlab flowables, so the PDF stays in
sync with the markdown/HTML automatically.
"""
from __future__ import annotations

import re
from typing import Optional

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image,
)

from .reconcile import Reconciliation
from .report import markdown

# Helvetica lacks some glyphs; map the few we use to safe equivalents.
_SUBST = {
    "→": " - ", "⇒": "=>", "✓": "Y", "✈": ">", "—": "-", "−": "-",
    "·": ".", "°": " deg ",
}


def _ascii(s: str) -> str:
    for k, v in _SUBST.items():
        s = s.replace(k, v)
    return s


def _cell(s: str) -> str:
    s = _ascii(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"\*(.+?)\*", r"<i>\1</i>", s)
    s = re.sub(r"`(.+?)`", r"\1", s)
    return s


_SEP = re.compile(r"^\|[\s:\-|]+\|$")


def save_pdf(rec: Reconciliation, path: str, map_path: Optional[str] = None) -> str:
    styles = getSampleStyleSheet()
    h1 = ParagraphStyle("h1", parent=styles["Title"], fontSize=15, spaceAfter=6)
    h2 = ParagraphStyle("h2", parent=styles["Heading2"], fontSize=11, spaceBefore=10, spaceAfter=3)
    h3 = ParagraphStyle("h3", parent=styles["Heading3"], fontSize=9, spaceBefore=6, spaceAfter=2)
    body = ParagraphStyle("body", parent=styles["BodyText"], fontSize=7.5, leading=10)
    cell = ParagraphStyle("cell", parent=styles["BodyText"], fontSize=6, leading=7)
    cell_r = ParagraphStyle("cellr", parent=cell, alignment=2)  # right

    doc = SimpleDocTemplate(
        path, pagesize=landscape(A4),
        leftMargin=12 * mm, rightMargin=12 * mm,
        topMargin=12 * mm, bottomMargin=12 * mm,
        title=f"Reconciliation {rec.nav.departure}-{rec.nav.destination}",
    )
    avail = doc.width
    flow = []
    table_rows = []
    inserted_map = [False]

    def flush_table():
        if not table_rows:
            return
        header, *rows = table_rows
        ncols = len(header)
        data = [[Paragraph(_cell(c), cell_r if j else cell) for j, c in enumerate(header)]]
        for r in rows:
            data.append([Paragraph(_cell(c), cell_r if j else cell)
                         for j, c in enumerate(r)])
        weights = [2.0] + [1.0] * (ncols - 1)
        unit = avail / sum(weights)
        col_widths = [w * unit for w in weights]
        tbl = Table(data, colWidths=col_widths, repeatRows=1)
        tbl.setStyle(TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#cccccc")),
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#eeeeee")),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#fafafa")]),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("TOPPADDING", (0, 0), (-1, -1), 1),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
        ]))
        flow.append(tbl)
        flow.append(Spacer(1, 4))
        table_rows.clear()

    def add_map():
        if map_path and not inserted_map[0]:
            try:
                img = Image(map_path)
                scale = min(avail / img.imageWidth,
                            (doc.height * 0.92) / img.imageHeight, 1.0)
                img.drawWidth = img.imageWidth * scale
                img.drawHeight = img.imageHeight * scale
                flow.append(img)
                flow.append(Spacer(1, 6))
            except Exception:
                pass
            inserted_map[0] = True

    for line in markdown(rec).splitlines():
        if line.startswith("|"):
            if _SEP.match(line):
                continue
            table_rows.append([c.strip() for c in line.strip().strip("|").split("|")])
            continue
        flush_table()
        if line.startswith("# "):
            flow.append(Paragraph(_cell(line[2:]), h1))
        elif line.startswith("## "):
            flow.append(Paragraph(_cell(line[3:]), h2))
        elif line.startswith("**") and line.endswith("**"):
            flow.append(Paragraph(_cell(line), h3))
        elif line.strip():
            flow.append(Paragraph(_cell(line), body))
            add_map()  # place the map right after the first paragraph (route line)
    flush_table()
    doc.build(flow)
    return path
