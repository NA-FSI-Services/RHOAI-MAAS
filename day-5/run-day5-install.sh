#!/usr/bin/env bash
# Day 5 — External LiteLLM model via MaaS ExternalModel CR
set -uo pipefail

CURL=/usr/bin/curl
DAY5_DIR="$(cd "$(dirname "$0")" && pwd)"
POC_DIR="$(cd "$DAY5_DIR/.." && pwd)"
LOG="$DAY5_DIR/day5-install.log"

# Provider key: pass via env or day-5/provider-key.env (gitignored)
if [ -f "$DAY5_DIR/provider-key.env" ]; then
  # shellcheck disable=SC1090
  source "$DAY5_DIR/provider-key.env"
fi
: "${LITELLM_PROVIDER_KEY:?Set LITELLM_PROVIDER_KEY or create day-5/provider-key.env}"

exec > >(tee "$LOG") 2>&1

echo "=== Day 5 Installation Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

run_capture() {
  local name="$1"; shift
  { echo "# $*"; echo "# $(date -u +"%Y-%m-%dT%H:%M:%SZ")"; echo "---"; "$@" 2>&1; } | tee "$DAY5_DIR/$name"
}

run_capture "00-state-before.txt" sh -c '
  oc get externalmodel,maasmodelref -A 2>&1 || true
  oc get httproute -n llm 2>&1 | grep -E "codellama|bbr" || true
'

echo ""
echo "=== Step 1: Provider secret (BBR-managed label required) ==="
oc create secret generic litellm-workshop-provider-key \
  --from-literal=api-key="${LITELLM_PROVIDER_KEY}" \
  -n llm --dry-run=client -o yaml | oc apply -f -
oc label secret litellm-workshop-provider-key -n llm \
  inference.networking.k8s.io/bbr-managed=true --overwrite
oc label secret litellm-workshop-provider-key -n llm \
  maas.opendatahub.io/day5=litellm-external --overwrite

echo ""
echo "=== Step 2: ExternalModel + MaaSModelRef ==="
oc apply -f "$DAY5_DIR/manifests/external-model.yaml"
oc apply -f "$DAY5_DIR/manifests/maas-model-ref.yaml"
sleep 8

echo ""
echo "=== Step 3: Subscriptions + AuthPolicies ==="
oc apply -f "$DAY5_DIR/manifests/subscription-patches.yaml"
oc apply -f "$DAY5_DIR/manifests/auth-policy-patches.yaml"
sleep 10

echo ""
echo "=== Step 4: HTTPRoute URL rewrite patch (LiteLLM path) ==="
oc apply -f "$DAY5_DIR/manifests/httproute-urlrewrite-patch.yaml"

echo ""
echo "=== Step 5: Ensure payload-processing images (Day 4 + credential injection) ==="
oc set image deployment/payload-pre-processing -n openshift-ingress \
  payload-pre-processing=quay.io/opendatahub/odh-ai-gateway-payload-processing:odh-stable 2>/dev/null || true
oc set image deployment/payload-processing -n openshift-ingress \
  payload-processing=quay.io/opendatahub/odh-ai-gateway-payload-processing:odh-stable 2>/dev/null || true
oc rollout status deployment/payload-processing -n openshift-ingress --timeout=180s 2>/dev/null || true

echo ""
echo "=== Step 6: Validation ==="
source "$POC_DIR/day-3/demo-env.sh" 2>/dev/null || true
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="${MAAS_URL:-https://maas.${CLUSTER_DOMAIN}}"
EXT_PATH="${MAAS_URL}/llm/codellama-7b-instruct/v1/chat/completions"

{
  echo "MAAS_URL=$MAAS_URL"
  echo "EXTERNAL_ENDPOINT=maas-rhdp.apps.maas.redhatworkshops.io"
  echo "MODEL=codellama-7b-instruct"
  echo ""
  oc get externalmodel,maasmodelref,secret/litellm-workshop-provider-key -n llm 2>&1
  echo ""
  echo -n "model path (basic key): "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "$EXT_PATH" \
    -H "Authorization: Bearer ${BASIC_USER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"codellama-7b-instruct","messages":[{"role":"user","content":"Hello external model"}],"max_tokens":20}'
  echo -n "model path (advanced key): "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "$EXT_PATH" \
    -H "Authorization: Bearer ${ADVANCED_USER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"codellama-7b-instruct","messages":[{"role":"user","content":"Hello external model"}],"max_tokens":20}'
  echo -n "model path (no auth): "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "$EXT_PATH" \
    -H "Content-Type: application/json" \
    -d '{"model":"codellama-7b-instruct","messages":[{"role":"user","content":"Ping"}],"max_tokens":5}'
  echo -n "unified BBR (basic key): "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
    -H "Authorization: Bearer ${BASIC_USER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"codellama-7b-instruct","messages":[{"role":"user","content":"Hello"}],"max_tokens":15}'
} | tee "$DAY5_DIR/05-validation.txt"

run_capture "06-day5-final-state.txt" sh -c '
  oc get externalmodel,maasmodelref,httproute,authpolicy,serviceentry -n llm 2>&1 | grep -i codellama || true
  oc get maassubscription simulator-free granite-tiny-gpu-premium -n models-as-a-service -o jsonpath="{range .items[*]}{.metadata.name}{\": \"}{range .spec.modelRefs[*]}{.name}{\" \"}{end}{\"\\n\"}{end}"
'

echo "=== Day 5 Installation Complete ==="
