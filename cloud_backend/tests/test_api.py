import base64
import io
import os
import subprocess
import time
from pathlib import Path

import pytest
from openpyxl import load_workbook

from app import config, converters, main
from tests.conftest import b64

MIN_PDF = b"%PDF-1.4\n%fake but magic bytes are right\n"


def post(client, file_b64, target="docx", source="pdf", headers=None):
    return client.post(
        "/convert",
        json={"file": file_b64, "sourceFormat": source, "targetFormat": target},
        headers=headers or {},
    )


# --------------------------------------------------------------------------- #
# Health / auth / validation
# --------------------------------------------------------------------------- #

def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_unknown_route_uses_error_envelope(client):
    r = client.get("/nope")
    assert r.status_code == 404
    assert "error" in r.json()


def test_auth_disabled_when_api_key_unset(client, table_pdf):
    r = post(client, b64(table_pdf), target="xlsx")
    assert r.status_code == 200


def test_auth_required_when_api_key_set(client, monkeypatch, table_pdf):
    monkeypatch.setattr(config, "API_KEY", "s3cret")
    r = post(client, b64(table_pdf), target="xlsx")
    assert r.status_code == 401
    assert "error" in r.json()

    r = post(client, b64(table_pdf), target="xlsx", headers={"X-Api-Key": "wrong"})
    assert r.status_code == 401

    r = post(client, b64(table_pdf), target="xlsx", headers={"X-Api-Key": "s3cret"})
    assert r.status_code == 200


def test_bad_base64(client):
    r = post(client, "this is not base64!!!", target="xlsx")
    assert r.status_code == 400
    assert "base64" in r.json()["error"]


def test_base64_with_line_breaks_is_accepted(client, table_pdf):
    wrapped = base64.encodebytes(table_pdf).decode("ascii")  # MIME, 76-char lines
    assert "\n" in wrapped
    r = post(client, wrapped, target="xlsx")
    assert r.status_code == 200


def test_missing_file(client):
    r = client.post("/convert", json={"sourceFormat": "pdf", "targetFormat": "docx"})
    assert r.status_code == 400
    assert "error" in r.json()


def test_body_not_json(client):
    r = client.post("/convert", content=b"not json", headers={"Content-Type": "application/json"})
    assert r.status_code == 400
    assert "error" in r.json()


def test_non_pdf_rejected(client):
    r = post(client, b64(b"PK\x03\x04 this is a zip"), target="docx")
    assert r.status_code == 400
    assert r.json() == {"error": "Input is not a PDF"}


def test_unknown_target_format(client):
    r = post(client, b64(MIN_PDF), target="odt")
    assert r.status_code == 400
    assert "targetFormat" in r.json()["error"]


def test_unknown_source_format(client):
    r = post(client, b64(MIN_PDF), target="docx", source="docx")
    assert r.status_code == 400


def test_oversized_decoded_pdf(client, monkeypatch):
    monkeypatch.setattr(config, "MAX_PDF_BYTES", 1024)  # body cap stays large
    r = post(client, b64(b"%PDF-1.4\n" + b"0" * 2048), target="docx")
    assert r.status_code == 413
    assert "too large" in r.json()["error"]


def test_oversized_body_rejected_before_parsing(client, monkeypatch):
    monkeypatch.setattr(config, "MAX_BODY_BYTES", 1024)
    r = post(client, b64(b"%PDF-1.4\n" + b"0" * 4096), target="docx")
    assert r.status_code == 413


def test_default_limits_are_25mb():
    assert config.MAX_PDF_BYTES == 25 * 1024 * 1024
    # A max-size PDF, base64-encoded, must fit inside the body cap.
    assert config.MAX_BODY_BYTES > (config.MAX_PDF_BYTES + 2) // 3 * 4


# --------------------------------------------------------------------------- #
# XLSX (real pdfplumber + openpyxl, no mocks)
# --------------------------------------------------------------------------- #

def _load_xlsx(resp):
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert set(body) == {"content", "format"}
    assert body["format"] == "xlsx"
    return load_workbook(io.BytesIO(base64.b64decode(body["content"])))


def test_xlsx_extracts_tables(client, table_pdf):
    wb = _load_xlsx(post(client, b64(table_pdf), target="xlsx"))
    assert wb.sheetnames == ["Page 1 Table 1"]
    rows = [list(r) for r in wb.active.iter_rows(values_only=True)]
    assert rows[0] == ["Item", "Qty", "Price"]
    assert rows[1] == ["Apples", 3, 1.5]
    assert rows[2] == ["Pears", 10, 2.25]
    assert rows[3] == ["Plums", "007", 0.99]  # leading zeros preserved as text


def test_xlsx_text_fallback_when_no_tables(client, text_pdf):
    wb = _load_xlsx(post(client, b64(text_pdf), target="xlsx"))
    assert wb.sheetnames == ["Page 1", "Page 2"]
    rows = [list(r) for r in wb["Page 1"].iter_rows(values_only=True)]
    assert rows[0] == ["Name", "Score"]
    assert rows[1] == ["Alice", 42]
    assert rows[2] == ["Bob", 17]
    assert wb["Page 2"]["A1"].value == "Second page line"


def test_xlsx_corrupt_pdf_returns_error(client):
    r = post(client, b64(MIN_PDF), target="xlsx")
    assert r.status_code == 422
    assert "error" in r.json()


def test_safe_sheet_titles():
    used: set[str] = set()
    a = converters._safe_sheet_title("a/b:c*d?e[f]g\\h" + "x" * 40, used)
    b = converters._safe_sheet_title("a/b:c*d?e[f]g\\h" + "x" * 40, used)
    assert len(a) <= 31 and len(b) <= 31
    assert not set("[]*?/\\:") & set(a)
    assert a != b


# --------------------------------------------------------------------------- #
# DOCX / PPTX (LibreOffice subprocess mocked -- soffice is not installed here)
# --------------------------------------------------------------------------- #

class FakePopen:
    """Stands in for soffice: writes <stem>.<ext> into --outdir."""

    calls: list[list[str]] = []
    seen_dirs: list[Path] = []
    behaviour = "ok"

    def __init__(self, cmd, **kwargs):
        FakePopen.calls.append(cmd)
        self.cmd = cmd
        self.pid = os.getpid()
        self.returncode = None
        self.kwargs = kwargs

    def communicate(self, timeout=None):
        if FakePopen.behaviour == "timeout" and self.returncode is None:
            self.returncode = -9
            raise subprocess.TimeoutExpired(self.cmd, timeout)
        if FakePopen.behaviour == "fail":
            self.returncode = 1
            return b"", b"Error: source file could not be loaded"
        out_dir = Path(self.cmd[self.cmd.index("--outdir") + 1])
        src = Path(self.cmd[-1])
        FakePopen.seen_dirs.append(src.parent)
        ext = self.cmd[self.cmd.index("--convert-to") + 1].split(":")[0]
        (out_dir / f"{src.stem}.{ext}").write_bytes(b"PK\x03\x04fake-" + ext.encode())
        self.returncode = 0
        return b"", b""

    def kill(self):
        pass


@pytest.fixture
def fake_soffice(monkeypatch):
    FakePopen.calls = []
    FakePopen.seen_dirs = []
    FakePopen.behaviour = "ok"
    monkeypatch.setattr(converters.subprocess, "Popen", FakePopen)
    monkeypatch.setattr(converters.os, "killpg", lambda *a: None)
    return FakePopen


@pytest.mark.parametrize(
    "target,infilter,convert_to",
    [
        ("docx", "--infilter=writer_pdf_import", "docx:MS Word 2007 XML"),
        ("pptx", "--infilter=impress_pdf_import", "pptx"),
    ],
)
def test_soffice_targets(client, fake_soffice, target, infilter, convert_to):
    r = post(client, b64(MIN_PDF), target=target)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["format"] == target
    assert base64.b64decode(body["content"]) == b"PK\x03\x04fake-" + target.encode()

    cmd = fake_soffice.calls[-1]
    assert "--headless" in cmd
    assert infilter in cmd
    assert cmd[cmd.index("--convert-to") + 1] == convert_to
    assert any(a.startswith("-env:UserInstallation=file:///") for a in cmd)
    assert fake_soffice.calls[-1][-1].endswith("input.pdf")


def test_soffice_profile_is_unique_per_request(client, fake_soffice):
    post(client, b64(MIN_PDF), target="docx")
    post(client, b64(MIN_PDF), target="docx")
    profiles = [next(a for a in c if a.startswith("-env:UserInstallation")) for c in fake_soffice.calls]
    assert len(set(profiles)) == 2


def test_soffice_failure_returns_error(client, fake_soffice):
    fake_soffice.behaviour = "fail"
    r = post(client, b64(MIN_PDF), target="docx")
    assert r.status_code == 500
    assert "LibreOffice failed" in r.json()["error"]


def test_soffice_timeout_returns_504(client, fake_soffice):
    fake_soffice.behaviour = "timeout"
    r = post(client, b64(MIN_PDF), target="pptx")
    assert r.status_code == 504
    assert "timed out" in r.json()["error"]


def test_soffice_missing_returns_503(client, monkeypatch):
    monkeypatch.setattr(config, "SOFFICE_BIN", "/nonexistent/soffice")
    r = post(client, b64(MIN_PDF), target="docx")
    assert r.status_code == 503
    assert r.json() == {"error": "LibreOffice is not installed on the server"}


# --------------------------------------------------------------------------- #
# Privacy: temp files
# --------------------------------------------------------------------------- #

def test_temp_dirs_deleted_after_success(client, work_root, fake_soffice, table_pdf):
    post(client, b64(MIN_PDF), target="docx")
    post(client, b64(table_pdf), target="xlsx")
    assert fake_soffice.seen_dirs, "conversion should have run inside a temp dir"
    for d in fake_soffice.seen_dirs:
        assert d.parent == work_root
        assert not d.exists()
    assert list(work_root.iterdir()) == []
    assert main._active_dirs == set()


def test_temp_dirs_deleted_after_failure(client, work_root, fake_soffice):
    fake_soffice.behaviour = "fail"
    post(client, b64(MIN_PDF), target="docx")
    post(client, b64(MIN_PDF), target="xlsx")
    assert list(work_root.iterdir()) == []


def test_sweeper_removes_stale_entries_but_not_active(work_root, monkeypatch):
    work_root.mkdir(parents=True)
    old = work_root / "req_old"
    old.mkdir()
    (old / "input.pdf").write_bytes(b"%PDF-")
    fresh = work_root / "req_fresh"
    fresh.mkdir()
    active = work_root / "req_active"
    active.mkdir()
    past = time.time() - 120
    os.utime(old, (past, past))
    os.utime(active, (past, past))
    monkeypatch.setattr(main, "_active_dirs", {str(active)})

    assert main.sweep_once() == 1
    assert not old.exists()
    assert fresh.exists()
    assert active.exists()
