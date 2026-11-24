#!/usr/bin/env bash
# Build and deploy the conversion service to Google Cloud Run.
#
# Usage:
#   export GCP_PROJECT=my-project        # defaults to the active gcloud project
#   export GCP_REGION=us-central1        # optional
#   export API_KEY=$(openssl rand -hex 32)   # optional; empty = no auth (not recommended). No commas.
#   ./deploy.sh
set -euo pipefail

SERVICE="${SERVICE_NAME:-docuscan-convert}"
REGION="${GCP_REGION:-us-central1}"
PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
MAX_INSTANCES="${MAX_INSTANCES:-10}"

if [[ -z "${PROJECT}" ]]; then
  echo "Set GCP_PROJECT or run 'gcloud config set project <id>'." >&2
  exit 1
fi
if [[ -z "${API_KEY:-}" ]]; then
  echo "WARNING: API_KEY is not set; the service will accept unauthenticated requests." >&2
fi

cd "$(dirname "$0")"

# --source builds the Dockerfile with Cloud Build and pushes to Artifact Registry.
gcloud run deploy "${SERVICE}" \
  --project "${PROJECT}" \
  --region "${REGION}" \
  --source . \
  --platform managed \
  --allow-unauthenticated \
  --memory 2Gi \
  --cpu 2 \
  --concurrency 4 \
  --timeout 120 \
  --min-instances 0 \
  --max-instances "${MAX_INSTANCES}" \
  --set-env-vars "API_KEY=${API_KEY:-},MAX_CONCURRENT_SOFFICE=2,SOFFICE_TIMEOUT=90"

gcloud run services describe "${SERVICE}" --project "${PROJECT}" --region "${REGION}" \
  --format 'value(status.url)'
