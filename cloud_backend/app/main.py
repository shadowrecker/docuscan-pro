"""DocuScan Pro cloud conversion microservice.

Contract (matches CloudConversionHandler.kt / CloudConversionHandler.swift):

    POST /convert
    Content-Type: application/json
    X-Api-Key: <optional; required only when the API_KEY env var is set>
    {"file": "<base64 PDF>", "sourceFormat": "pdf", "targetFormat": "docx|xlsx|pptx"}

    200 -> {"content": "<base64 output>", "format": "<targetFormat>"}
    4xx/5xx -> {"error": "<message>"}

Stateless: every request works in its own temp dir that is deleted in a
``finally`` before the response is sent; a background sweeper removes anything
older than 60 s as a second line of defence. File contents are never logged.
"""

from __future__ import annotations

import asyncio
import base64
import binascii
import hmac
import json
import logging
import shutil
import tempfile
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import config
from .converters import ConversionError, convert_to_xlsx, convert_with_soffice

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("docuscan.api")

# Temp dirs currently in use by an in-flight request; the sweeper skips these.
_active_dirs: set[str] = set()
_soffice_semaphore: asyncio.Semaphore | None = None


# --------------------------------------------------------------------------- #
# Temp-file sweeper
# --------------------------------------------------------------------------- #

def sweep_once(max_age: float | None = None) -> int:
    """Delete entries in WORK_ROOT older than ``max_age`` seconds. Returns count removed."""
    max_age = config.MAX_FILE_AGE_SECONDS if max_age is None else max_age
    root = config.WORK_ROOT
    if not root.is_dir():
        return 0
    now = time.time()
    removed = 0
    for entry in root.iterdir():
        if str(entry) in _active_dirs:
            continue
        try:
            if now - entry.stat().st_mtime < max_age:
                continue
            if entry.is_dir() and not entry.is_symlink():
                shutil.rmtree(entry, ignore_errors=True)
            else:
                entry.unlink(missing_ok=True)
            removed += 1
        except FileNotFoundError:
            continue
        except OSError as exc:
            log.warning("sweeper could not remove an entry: %s", type(exc).__name__)
    return removed


async def _sweeper_loop() -> None:
    while True:
        try:
            removed = await run_in_threadpool(sweep_once)
            if removed:
                log.info("sweeper removed %d stale temp entr%s", removed, "y" if removed == 1 else "ies")
        except Exception:  # never let the sweeper die
            log.exception("sweeper iteration failed")
        await asyncio.sleep(config.SWEEP_INTERVAL_SECONDS)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global _soffice_semaphore
    _soffice_semaphore = asyncio.Semaphore(config.MAX_CONCURRENT_SOFFICE)
    config.WORK_ROOT.mkdir(parents=True, exist_ok=True)
    task = asyncio.create_task(_sweeper_loop())
    try:
        yield
    finally:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="DocuScan Pro Cloud Conversion", version="1.0.0", lifespan=lifespan,
              docs_url=None, redoc_url=None, openapi_url=None)


# --------------------------------------------------------------------------- #
# Error envelope: every non-200 response is {"error": "..."}
# --------------------------------------------------------------------------- #

def _error(status: int, message: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": message})


@app.exception_handler(StarletteHTTPException)
async def _http_exc_handler(_request: Request, exc: StarletteHTTPException):
    return _error(exc.status_code, str(exc.detail))


@app.exception_handler(RequestValidationError)
async def _validation_exc_handler(_request: Request, _exc: RequestValidationError):
    return _error(400, "Invalid request")


@app.exception_handler(Exception)
async def _unhandled_exc_handler(_request: Request, exc: Exception):
    log.error("unhandled error: %s", type(exc).__name__)
    return _error(500, "Internal server error")


# --------------------------------------------------------------------------- #
# Routes
# --------------------------------------------------------------------------- #

@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


def _authorized(request: Request) -> bool:
    expected = config.API_KEY
    if not expected:
        return True
    provided = request.headers.get("x-api-key", "")
    return hmac.compare_digest(provided.encode("utf-8"), expected.encode("utf-8"))


async def _read_body_capped(request: Request) -> bytes | None:
    """Read the request body, returning None if it exceeds MAX_BODY_BYTES."""
    declared = request.headers.get("content-length")
    if declared is not None:
        try:
            if int(declared) > config.MAX_BODY_BYTES:
                return None
        except ValueError:
            pass
    chunks: list[bytes] = []
    size = 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > config.MAX_BODY_BYTES:
            return None
        chunks.append(chunk)
    return b"".join(chunks)


@app.post("/convert")
async def convert(request: Request):
    request_id = uuid.uuid4().hex[:12]
    started = time.monotonic()

    if not _authorized(request):
        return _error(401, "Invalid or missing API key")

    body = await _read_body_capped(request)
    if body is None:
        return _error(413, f"File too large (max {config.MAX_PDF_BYTES // (1024 * 1024)} MB)")

    try:
        payload = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return _error(400, "Request body must be JSON")
    del body
    if not isinstance(payload, dict):
        return _error(400, "Request body must be a JSON object")

    file_b64 = payload.get("file")
    source = str(payload.get("sourceFormat", "pdf")).lower().strip()
    target = str(payload.get("targetFormat", "")).lower().strip()

    if source != "pdf":
        return _error(400, f"Unsupported sourceFormat '{source}' (only 'pdf' is supported)")
    if target not in config.SUPPORTED_TARGETS:
        return _error(
            400,
            f"Unsupported targetFormat '{target}' (expected one of: {', '.join(config.SUPPORTED_TARGETS)})",
        )
    if not isinstance(file_b64, str) or not file_b64:
        return _error(400, "Missing 'file' (base64-encoded PDF)")

    try:
        # Tolerate MIME-style line breaks (e.g. Android Base64.DEFAULT).
        pdf_bytes = base64.b64decode("".join(file_b64.split()), validate=True)
    except (binascii.Error, ValueError):
        return _error(400, "'file' is not valid base64")
    del file_b64, payload

    if len(pdf_bytes) > config.MAX_PDF_BYTES:
        return _error(413, f"File too large (max {config.MAX_PDF_BYTES // (1024 * 1024)} MB)")
    if not pdf_bytes.startswith(b"%PDF-"):
        return _error(400, "Input is not a PDF")

    config.WORK_ROOT.mkdir(parents=True, exist_ok=True)
    tmp = tempfile.TemporaryDirectory(prefix="req_", dir=str(config.WORK_ROOT))
    _active_dirs.add(tmp.name)
    try:
        pdf_path = Path(tmp.name) / "input.pdf"
        pdf_path.write_bytes(pdf_bytes)
        input_size = len(pdf_bytes)
        del pdf_bytes

        try:
            if target == "xlsx":
                out_path = await run_in_threadpool(convert_to_xlsx, pdf_path)
            else:
                assert _soffice_semaphore is not None
                async with _soffice_semaphore:
                    out_path = await run_in_threadpool(convert_with_soffice, pdf_path, target)
        except ConversionError as exc:
            log.info("req=%s target=%s in=%dB failed: %s", request_id, target, input_size, exc)
            return _error(exc.status_code, str(exc))

        content = base64.b64encode(out_path.read_bytes()).decode("ascii")
        log.info(
            "req=%s target=%s in=%dB out=%dB took=%.2fs",
            request_id, target, input_size, len(content) * 3 // 4, time.monotonic() - started,
        )
        return JSONResponse(status_code=200, content={"content": content, "format": target})
    finally:
        # Delete input + output immediately, before the response is sent.
        tmp.cleanup()
        _active_dirs.discard(tmp.name)
