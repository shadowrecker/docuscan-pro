"""Runtime configuration, read from environment variables."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path


def _int_env(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


# Optional shared secret. When empty/unset, authentication is skipped.
API_KEY: str = os.environ.get("API_KEY", "")

# Maximum size of the *decoded* PDF.
MAX_PDF_BYTES: int = _int_env("MAX_PDF_BYTES", 25 * 1024 * 1024)

# Maximum size of the raw JSON request body: base64 inflates by 4/3, plus
# a little room for the JSON envelope and any line breaks in the base64.
MAX_BODY_BYTES: int = MAX_PDF_BYTES * 4 // 3 + 64 * 1024 + MAX_PDF_BYTES // 50

# LibreOffice binary and per-conversion timeout (seconds).
SOFFICE_BIN: str = os.environ.get("SOFFICE_BIN", "soffice")
SOFFICE_TIMEOUT: int = _int_env("SOFFICE_TIMEOUT", 90)

# Max concurrent LibreOffice processes per container.
MAX_CONCURRENT_SOFFICE: int = _int_env("MAX_CONCURRENT_SOFFICE", 2)

# Root under which every per-request temp dir is created. The sweeper only
# ever touches entries inside this directory.
WORK_ROOT: Path = Path(
    os.environ.get("WORK_ROOT", os.path.join(tempfile.gettempdir(), "docuscan_work"))
)

# Anything left in WORK_ROOT longer than this (seconds) is deleted.
MAX_FILE_AGE_SECONDS: int = _int_env("MAX_FILE_AGE_SECONDS", 60)
SWEEP_INTERVAL_SECONDS: int = _int_env("SWEEP_INTERVAL_SECONDS", 15)

SUPPORTED_TARGETS = ("docx", "xlsx", "pptx")
