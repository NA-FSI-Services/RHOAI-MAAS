#!/usr/bin/env bash
# Day 2 — MaaS activation, PostgreSQL, model deployment
set -uo pipefail

GUIDE_DIR="$(cd "$(dirname "$0")/../work/rhoai-maas-guide" && pwd)"
OUT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$OUT_DIR/day2-install.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

exec > >(tee "$LOG") 2>&1

echo "=== Day 2 Installation Started: $TIMESTAMP ==="

run_capture() {
  local name="$1"; shift
  { echo "# $*"; echo "# $TIMESTAMP"; echo "---"; "$@" 2>&1; } | tee "$OUT_DIR/$name.txt"
}

# Snapshot before
run_capture "00-state-before.txt" sh -c '
  oc get dsc default-dsc -o jsonpath="modelsAsService={.spec.components.kserve.modelsAsService.managementState} phase={.status.phase}{\"\n\"}"
  oc get secret maas-db-config -n redhat-ods-applications 2>&1 || true
  oc get llminferenceservice -n llm 2>&1 || true
  oc get maasmodelref,maassubscription,tenant -A 2>&1 || true
'

# Phase 3-6 via guide (skip verify for separate capture)
echo ""
echo "=== Running setup-maas.sh --from-phase 3 --model granite-tiny-gpu --skip-verify ==="
cd "$GUIDE_DIR"
./scripts/setup-maas.sh --from-phase 3 --model granite-tiny-gpu --skip-verify || echo "[WARN] setup-maas.sh exit $?"

# Deploy granite + simulator explicitly (Qwen may have caused phase 5 skip)
echo ""
echo "=== Deploy granite-tiny-gpu ==="
./scripts/deploy-model.sh --model granite-tiny-gpu || echo "[WARN] granite deploy exit $?"

echo ""
echo "=== Deploy simulator ==="
./scripts/deploy-model.sh --model simulator || echo "[WARN] simulator deploy exit $?"

# Post-state capture
echo ""
echo "=== Post-install state ==="
run_capture "01-dsc-status.txt" oc get datasciencecluster default-dsc -o yaml
run_capture "02-maas-db.txt" sh -c 'oc get secret maas-db-config,postgres-creds -n redhat-ods-applications 2>&1; oc get deploy,pod -n redhat-ods-applications | grep -i postgres'
run_capture "03-maas-api.txt" sh -c 'oc get deploy,pod,svc -n redhat-ods-applications | grep maas-api; oc get deploy,pod,svc -n maas-api 2>&1'
run_capture "04-maas-crs.txt" oc get maasmodelref,maassubscription,tenant -A
run_capture "05-llminferenceservices.txt" oc get llminferenceservice -A -o wide
run_capture "06-pods-llm.txt" oc get pods -n llm -o wide

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
{
  echo "MAAS_URL=$MAAS_URL"
  echo -n "GET /v1/models: "; curl -sk -o /dev/null -w "HTTP %{http_code}\n" "${MAAS_URL}/v1/models"
  echo -n "GET /maas-api/health: "; curl -sk -o /dev/null -w "HTTP %{http_code}\n" "${MAAS_URL}/maas-api/health"
} | tee "$OUT_DIR/07-gateway-smoke-tests.txt"

{
  echo "=== Day 2 Summary ==="
  echo "Captured: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo ""
  oc get datasciencecluster default-dsc -o jsonpath='ModelsAsServiceReady: {range .status.conditions[?(@.type=="ModelsAsServiceReady")]}{.status}{" ("}{.message}{")"}{end}{"\n"}'
  echo ""
  echo "=== MaaS CRs ==="
  oc get maasmodelref,maassubscription,tenant -A 2>&1
  echo ""
  echo "=== Models (llm ns) ==="
  oc get llminferenceservice -n llm
  echo ""
  echo "=== PostgreSQL ==="
  oc get deploy postgres -n redhat-ods-applications 2>&1
  echo ""
  cat "$OUT_DIR/07-gateway-smoke-tests.txt"
} | tee "$OUT_DIR/08-day2-summary.txt"

echo "=== Day 2 Installation Complete ==="
