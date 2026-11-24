# DocuScan Pro – Cloud Conversion Service

Opt-in, stateless microservice for the conversions the on-device engine can't
handle well (complex layouts):

| Target | Feature | Engine |
|---|---|---|
| `docx` | C-02 PDF→Word | LibreOffice headless (`writer_pdf_import`) |
| `xlsx` | C-03 PDF→Excel | `pdfplumber` table extraction → `openpyxl` (one sheet per table; falls back to one sheet per page of text lines, columns split on 2+ spaces) |
| `pptx` | C-04 PDF→PowerPoint | LibreOffice headless (`impress_pdf_import`) |

## API

```
POST /convert
Content-Type: application/json
X-Api-Key: <key>            # required only if the server has API_KEY set

{"file": "<base64 PDF>", "sourceFormat": "pdf", "targetFormat": "docx|xlsx|pptx"}
```

- `200` → `{"content": "<base64 output>", "format": "<targetFormat>"}`
- errors → `{"error": "..."}` with `400` (bad JSON/base64, not a PDF, unknown format),
  `401` (API key), `413` (PDF > 25 MB), `422` (unreadable PDF), `500` (LibreOffice
  failed), `503` (LibreOffice missing), `504` (conversion > 90 s).

`GET /healthz` → `{"status": "ok"}`.

## Run locally

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest              # soffice is mocked in tests
.venv/bin/uvicorn app.main:app --port 8080
```

XLSX works without LibreOffice; DOCX/PPTX need `soffice` on `PATH` (or set `SOFFICE_BIN`).

## Docker

```bash
docker build -t docuscan-convert .
docker run --rm -p 8080:8080 -e API_KEY=dev docuscan-convert
curl localhost:8080/healthz
```

## Deploy to Cloud Run

```bash
export GCP_PROJECT=your-project GCP_REGION=us-central1
export API_KEY=$(openssl rand -hex 32)
./deploy.sh      # 2 GiB, 2 vCPU, concurrency 4, timeout 120 s, 0–10 instances
```

Map `api.docuscanpro.com` to the service with a Cloud Run domain mapping or a
load balancer so `https://api.docuscanpro.com/convert` resolves.

## Pointing the app at it

In `lib/core/constants/app_constants.dart`:

- `AppConstants.cloudConversionBaseUrl` – full URL including `/convert`
  (e.g. `https://api.docuscanpro.com/convert` or the `*.run.app` URL + `/convert`).
- `AppConstants.cloudConversionApiKey` – same value as the server's `API_KEY`;
  sent as the `X-Api-Key` header.

## Environment variables

| Var | Default | Purpose |
|---|---|---|
| `PORT` | `8080` | Listen port (set by Cloud Run) |
| `API_KEY` | unset | If set, `X-Api-Key` must match (constant-time compare) |
| `MAX_PDF_BYTES` | 26214400 | Decoded PDF limit (25 MB) |
| `SOFFICE_BIN` | `soffice` | LibreOffice binary |
| `SOFFICE_TIMEOUT` | `90` | Per-conversion timeout (s) |
| `MAX_CONCURRENT_SOFFICE` | `2` | LibreOffice processes per container |
| `WORK_ROOT` | `$TMPDIR/docuscan_work` | Parent of per-request temp dirs |
| `MAX_FILE_AGE_SECONDS` | `60` | Sweeper deletes anything older than this |

## Privacy guarantees

- No database, no object storage, no persistent disk. Nothing is retained.
- Each request uses its own `TemporaryDirectory` (input PDF, output, and the
  per-request LibreOffice profile). It is deleted in a `finally` block **before**
  the response is sent – on success and on failure.
- A background sweeper deletes anything in `WORK_ROOT` older than 60 s (except
  dirs of requests still converting) as a second guarantee. On Cloud Run, `/tmp`
  is in-memory and vanishes with the instance.
- Logs contain only request id, target format, byte sizes, duration and error
  type – never file contents or file names.
- The PDF arrives over HTTPS (TLS terminated by Cloud Run).

## Cost notes

- `min-instances 0`: no traffic, no cost (cold start ~5–10 s, LibreOffice image ~600 MB).
- Billed per request-time at 2 vCPU / 2 GiB. Typical conversions take 1–10 s;
  the Cloud Run free tier (180k vCPU-s, 360k GiB-s per month) covers roughly
  10–30k conversions/month.
- `max-instances` caps worst-case spend; the app also limits users to
  `maxCloudConversionsPerDay`.
- XLSX is pure Python and cheap; DOCX/PPTX dominate cost.
- CPU is throttled outside requests (default), so the sweeper runs only while
  the instance is serving – fine, because request cleanup is synchronous.
