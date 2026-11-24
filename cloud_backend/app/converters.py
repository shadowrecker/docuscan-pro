"""Blocking conversion routines. Run these in a worker thread, never on the event loop.

Every function takes the path of an input PDF inside a per-request temp dir and
writes its output into that same directory, returning the output path.
"""

from __future__ import annotations

import logging
import os
import re
import signal
import subprocess
from pathlib import Path

from . import config

log = logging.getLogger("docuscan.converters")


class ConversionError(Exception):
    """Raised when a conversion fails. The message is safe to return to clients."""

    def __init__(self, message: str, status_code: int = 422):
        super().__init__(message)
        self.status_code = status_code


# --------------------------------------------------------------------------- #
# LibreOffice (DOCX / PPTX)
# --------------------------------------------------------------------------- #

# target -> (import filter, export filter spec)
_SOFFICE_FILTERS = {
    "docx": ("writer_pdf_import", 'docx:MS Word 2007 XML'),
    "pptx": ("impress_pdf_import", "pptx"),
}


def convert_with_soffice(pdf_path: Path, target: str) -> Path:
    """Convert ``pdf_path`` to ``target`` (docx|pptx) using headless LibreOffice."""
    if target not in _SOFFICE_FILTERS:
        raise ConversionError(f"Unsupported LibreOffice target: {target}")
    infilter, convert_to = _SOFFICE_FILTERS[target]

    workdir = pdf_path.parent
    out_dir = workdir / "out"
    out_dir.mkdir(exist_ok=True)
    # Unique LibreOffice profile per request so concurrent instances never share
    # a user installation (which would make the second one silently no-op).
    # It lives inside the request's temp dir, so it is deleted with it.
    profile_dir = workdir / "lo_profile"

    cmd = [
        config.SOFFICE_BIN,
        "--headless",
        "--norestore",
        "--nolockcheck",
        "--nodefault",
        "--nologo",
        f"-env:UserInstallation={profile_dir.as_uri()}",
        f"--infilter={infilter}",
        "--convert-to",
        convert_to,
        "--outdir",
        str(out_dir),
        str(pdf_path),
    ]
    env = dict(os.environ)
    env["HOME"] = str(workdir)  # non-root container user may have no writable home

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            cwd=str(workdir),
            start_new_session=True,  # own process group so we can kill soffice.bin too
        )
    except FileNotFoundError as exc:
        raise ConversionError("LibreOffice is not installed on the server", 503) from exc

    try:
        _stdout, stderr = proc.communicate(timeout=config.SOFFICE_TIMEOUT)
    except subprocess.TimeoutExpired:
        _kill_group(proc)
        proc.communicate()
        raise ConversionError(
            f"Conversion timed out after {config.SOFFICE_TIMEOUT} seconds", 504
        )

    expected = out_dir / f"{pdf_path.stem}.{target}"
    if proc.returncode != 0 or not expected.is_file() or expected.stat().st_size == 0:
        # stderr from LibreOffice contains only paths/filter messages, never content.
        log.warning(
            "soffice failed rc=%s target=%s stderr=%s",
            proc.returncode,
            target,
            (stderr or b"")[:500].decode("utf-8", "replace"),
        )
        raise ConversionError(f"LibreOffice failed to convert PDF to {target}", 500)
    return expected


def _kill_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        proc.kill()


# --------------------------------------------------------------------------- #
# pdfplumber + openpyxl (XLSX)
# --------------------------------------------------------------------------- #

_INVALID_SHEET_CHARS = re.compile(r"[\[\]\*\?/\\:]")
_COLUMN_SPLIT = re.compile(r"\s{2,}")
# Numbers without leading zeros (so IDs / zip codes like "007" stay text).
_NUMBER_RE = re.compile(r"^-?(0|[1-9]\d{0,14})(\.\d+)?$")


def _safe_sheet_title(title: str, used: set[str]) -> str:
    base = _INVALID_SHEET_CHARS.sub("_", title).strip("'").strip() or "Sheet"
    base = base[:31]
    candidate, n = base, 2
    while candidate.lower() in used:
        suffix = f"_{n}"
        candidate = base[: 31 - len(suffix)] + suffix
        n += 1
    used.add(candidate.lower())
    return candidate


def _clean_cell(value):
    from openpyxl.cell.cell import ILLEGAL_CHARACTERS_RE

    if value is None:
        return None
    text = ILLEGAL_CHARACTERS_RE.sub("", str(value)).strip()
    if not text:
        return None
    compact = text.replace(",", "") if re.fullmatch(r"-?\d{1,3}(,\d{3})+(\.\d+)?", text) else text
    if _NUMBER_RE.match(compact):
        try:
            return int(compact) if "." not in compact else float(compact)
        except ValueError:
            pass
    return text


def _autosize(ws) -> None:
    from openpyxl.utils import get_column_letter

    widths: dict[int, int] = {}
    for row in ws.iter_rows():
        for cell in row:
            if cell.value is not None:
                length = max(len(line) for line in str(cell.value).splitlines() or [""])
                widths[cell.column] = max(widths.get(cell.column, 0), length)
    for col, width in widths.items():
        ws.column_dimensions[get_column_letter(col)].width = min(max(width + 2, 8), 60)


def convert_to_xlsx(pdf_path: Path) -> Path:
    """Extract every table from every page into its own sheet.

    Falls back to one sheet per page of text lines (columns split on runs of
    2+ spaces) when no tables are detected anywhere in the document.
    """
    import pdfplumber
    from openpyxl import Workbook

    out_path = pdf_path.parent / "out.xlsx"
    wb = Workbook()
    wb.remove(wb.active)
    used: set[str] = set()

    try:
        with pdfplumber.open(str(pdf_path)) as pdf:
            tables_found = 0
            for page_no, page in enumerate(pdf.pages, start=1):
                for t_no, table in enumerate(page.extract_tables() or [], start=1):
                    rows = [r for r in table if r and any(c not in (None, "") for c in r)]
                    if not rows:
                        continue
                    tables_found += 1
                    ws = wb.create_sheet(_safe_sheet_title(f"Page {page_no} Table {t_no}", used))
                    for row in rows:
                        ws.append([_clean_cell(c) for c in row])
                    _autosize(ws)

            if tables_found == 0:
                any_text = False
                for page_no, page in enumerate(pdf.pages, start=1):
                    ws = wb.create_sheet(_safe_sheet_title(f"Page {page_no}", used))
                    text = page.extract_text(layout=True) or ""
                    for line in text.splitlines():
                        line = line.strip()
                        if not line:
                            continue
                        any_text = True
                        ws.append([_clean_cell(c) for c in _COLUMN_SPLIT.split(line)])
                    _autosize(ws)
                if not wb.worksheets:
                    wb.create_sheet("Sheet1")
                if not any_text:
                    wb.worksheets[0]["A1"] = (
                        "No extractable text found in this PDF (it may be a scanned image)."
                    )
    except ConversionError:
        raise
    except Exception as exc:  # pdfminer raises a zoo of exception types
        log.warning("pdfplumber failed: %s", type(exc).__name__)
        raise ConversionError("Could not read PDF (corrupt or encrypted?)") from exc

    wb.save(str(out_path))
    return out_path
