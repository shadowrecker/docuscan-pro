import base64
import io

import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app


@pytest.fixture
def work_root(tmp_path, monkeypatch):
    root = tmp_path / "work"
    monkeypatch.setattr(config, "WORK_ROOT", root)
    monkeypatch.setattr(config, "API_KEY", "")
    return root


@pytest.fixture
def client(work_root):
    with TestClient(app) as c:
        yield c


def _pdf_with_table() -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Table, TableStyle
    from reportlab.lib.styles import getSampleStyleSheet

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4)
    data = [
        ["Item", "Qty", "Price"],
        ["Apples", "3", "1.50"],
        ["Pears", "10", "2.25"],
        ["Plums", "007", "0.99"],
    ]
    table = Table(data)
    table.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), 0.5, colors.black)]))
    doc.build([Paragraph("Invoice", getSampleStyleSheet()["Title"]), table])
    return buf.getvalue()


def _pdf_text_only() -> bytes:
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfgen import canvas

    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    c.setFont("Courier", 11)
    c.drawString(72, 750, "Name        Score")
    c.drawString(72, 735, "Alice       42")
    c.drawString(72, 720, "Bob         17")
    c.showPage()
    c.drawString(72, 750, "Second page line")
    c.save()
    return buf.getvalue()


@pytest.fixture
def table_pdf() -> bytes:
    return _pdf_with_table()


@pytest.fixture
def text_pdf() -> bytes:
    return _pdf_text_only()


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")
