# DocuScan Pro cloud conversion microservice (Cloud Run).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8080 \
    WORK_ROOT=/tmp/docuscan_work

# LibreOffice: writer (DOCX), impress (PPTX), draw (required by the PDF import filters).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libreoffice-writer libreoffice-impress libreoffice-draw \
      fonts-dejavu fonts-liberation \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app

RUN useradd --system --uid 10001 --create-home --home-dir /home/app app
USER app

EXPOSE 8080
# Cloud Run injects $PORT. One worker: Cloud Run scales by instances, and the
# in-process semaphore caps concurrent LibreOffice processes per container.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1 --timeout-keep-alive 5 --no-access-log"]
