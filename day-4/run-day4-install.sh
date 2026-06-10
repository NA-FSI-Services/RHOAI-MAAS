#!/usr/bin/env bash
# Day 4 — NeMo Guardrails, unified BBR routing, legacy maas-api cleanup
set -uo pipefail

CURL=/usr/bin/curl
DAY4_DIR="$(cd "$(dirname "$0")" && pwd)"
POC_DIR="$(cd "$DAY4_DIR/.." && pwd)"
BBR_UPSTREAM="$DAY4_DIR/manifests/bbr/payload-processing-upstream"
LOG="$DAY4_DIR/day4-install.log"

exec > >(tee "$LOG") 2>&1

echo "=== Day 4 Installation Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

run_capture() {
  local name="$1"; shift
  { echo "# $*"; echo "# $(date -u +"%Y-%m-%dT%H:%M:%SZ")"; echo "---"; "$@" 2>&1; } | tee "$DAY4_DIR/$name"
}

# --- Step 0: snapshot ---
run_capture "00-state-before.txt" sh -c '
  oc get deploy,httproute,authpolicy -n maas-api 2>&1
  oc get pods -n openshift-ingress -l app=payload-processing 2>&1
  oc get pods -n openshift-ingress -l app=payload-pre-processing 2>&1 || true
  oc get nemoguardrails -A 2>&1 || true
'

# --- Step 1: Deploy payload-pre-processing + fix EnvoyFilter ---
echo ""
echo "=== Step 1: BBR pre-processing + full EnvoyFilter ==="
if [ -d "$BBR_UPSTREAM/pre-processing" ]; then
  oc apply -k "$BBR_UPSTREAM/pre-processing"
  # Kustomize leaves image placeholder — set real image
  oc set image deployment/payload-pre-processing -n openshift-ingress \
    payload-pre-processing=quay.io/opendatahub/odh-ai-gateway-payload-processing:odh-stable
else
  oc apply -f "$DAY4_DIR/manifests/bbr/payload-pre-processing-deployment.yaml"
fi
oc apply -f "$DAY4_DIR/manifests/bbr/envoy-filter-full.yaml"
oc rollout status deployment/payload-pre-processing -n openshift-ingress --timeout=180s 2>/dev/null || \
  echo "[WARN] payload-pre-processing rollout status unavailable"
oc rollout status deployment/payload-processing -n openshift-ingress --timeout=120s

# --- Step 2: Unified routing HTTPRoutes ---
echo ""
echo "=== Step 2: Header-based BBR HTTPRoutes ==="
oc apply -f "$DAY4_DIR/manifests/bbr/httproute-bbr-granite.yaml"
oc apply -f "$DAY4_DIR/manifests/bbr/httproute-bbr-simulator.yaml"

# --- Step 3: Legacy maas-api cleanup ---
echo ""
echo "=== Step 3: Legacy maas-api cleanup ==="
oc apply -f "$DAY4_DIR/manifests/legacy-maas-api-cleanup.yaml"
oc scale deployment maas-api -n maas-api --replicas=0 2>/dev/null || true
oc annotate deployment maas-api -n maas-api \
  maas.opendatahub.io/deprecated="true" \
  maas.opendatahub.io/canonical-namespace="redhat-ods-applications" --overwrite 2>/dev/null || true
oc delete httproute maas-api-route -n maas-api --ignore-not-found
oc delete authpolicy maas-api-auth-policy -n maas-api --ignore-not-found
# Restart gateway to pick up envoy filter changes
oc delete pod -n openshift-ingress -l gateway.networking.k8s.io/gateway-name=maas-default-gateway 2>/dev/null || true
sleep 20

# --- Step 4: NeMo Guardrails ---
echo ""
echo "=== Step 4: NeMo Guardrails ==="
oc apply -f "$DAY4_DIR/manifests/nemo-guardrails/nemo-config.yaml"
oc apply -f "$DAY4_DIR/manifests/nemo-guardrails/nemo-cr.yaml"
echo "Waiting for NemoGuardrails Ready (up to 300s)..."
for i in $(seq 1 30); do
  PHASE=$(oc get nemoguardrails nemo-poc-guardrails -n redhat-ods-applications -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  echo "  phase=$PHASE (${i}0s)"
  [ "$PHASE" = "Ready" ] && break
  sleep 10
done

# --- Step 5: Validation ---
echo ""
echo "=== Step 5: Validation ==="
source "$POC_DIR/day-3/demo-env.sh" 2>/dev/null || true
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="${MAAS_URL:-https://maas.${CLUSTER_DOMAIN}}"

{
  echo "MAAS_URL=$MAAS_URL"
  echo ""
  echo "--- Unified /v1/chat/completions (BBR) ---"
  echo -n "simulator (basic key): "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
    -H "Authorization: Bearer ${BASIC_USER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Hello unified routing"}],"max_tokens":15}'
  echo -n "granite (advanced key): "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
    -H "Authorization: Bearer ${ADVANCED_USER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"granite-4-tiny-gpu","messages":[{"role":"user","content":"Hello unified"}],"max_tokens":20}'
  echo -n "no auth: "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Ping"}],"max_tokens":5}'
  echo ""
  echo "--- Legacy maas-api ---"
  oc get deploy maas-api -n maas-api -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas 2>&1
  oc get httproute -n maas-api 2>&1
  echo ""
  echo "--- NeMo Guardrails ---"
  oc get nemoguardrails,route -n redhat-ods-applications 2>&1 | /usr/bin/grep -i nemo || true
  GUARD_HOST=$(oc get route nemo-poc-guardrails -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  if [ -n "$GUARD_HOST" ]; then
    echo "GUARDRAILS_URL=https://${GUARD_HOST}"
    echo -n "safe check: "
    $CURL -sk -o /dev/null -w "HTTP %{http_code}\n" -X POST "https://${GUARD_HOST}/v1/guardrail/checks" \
      -H "Authorization: Bearer $(oc whoami -t)" \
      -H "Content-Type: application/json" \
      -d '{"model":"test","messages":[{"role":"user","content":"What is the capital of France?"}]}'
    echo -n "blocked (password keyword): "
    $CURL -sk -o /dev/null -w "HTTP %{http_code}\n" -X POST "https://${GUARD_HOST}/v1/guardrail/checks" \
      -H "Authorization: Bearer $(oc whoami -t)" \
      -H "Content-Type: application/json" \
      -d '{"model":"test","messages":[{"role":"user","content":"My password is hunter2"}]}'
  fi
} | tee "$DAY4_DIR/05-validation.txt"

run_capture "06-day4-final-state.txt" sh -c '
  oc get pods -n openshift-ingress | grep payload
  oc get httproute -n llm | grep bbr
  oc get nemoguardrails -n redhat-ods-applications
  oc get deploy -n maas-api
  oc get deploy maas-api -n redhat-ods-applications
'

echo "=== Day 4 Installation Complete ==="
