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
  inference.llm-d.ai/ipp-managed=true --overwrite
oc label secret litellm-workshop-provider-key -n llm \
  maas.opendatahub.io/day5=litellm-external --overwrite

echo ""
echo "=== Step 2: RHOAI 3.5-ea IPP plumbing (NetworkPolicy + ExtProc attach + GATEWAY_NAME) ==="
oc apply -f "$DAY5_DIR/manifests/networkpolicy-payload-processing-maas-gateway.yaml"
oc apply -f "$DAY5_DIR/manifests/envoyfilter-payload-processing-extproc-attach.yaml"
# Managed EnvoyFilter/payload-processing may still use targetRefs; pin to MaaS gateway pods only
# so ExtProc does not break RHOAI Observe (PromQL application/x-www-form-urlencoded bodies).
if oc get envoyfilter payload-processing -n openshift-ingress >/dev/null 2>&1; then
  python3 - <<'PY'
import json, subprocess
raw = subprocess.check_output(["oc", "get", "envoyfilter", "payload-processing", "-n", "openshift-ingress", "-o", "json"])
d = json.loads(raw)
spec = d.setdefault("spec", {})
spec.pop("targetRefs", None)
spec["workloadSelector"] = {"labels": {"gateway.networking.k8s.io/gateway-name": "maas-default-gateway"}}
path = "/tmp/payload-processing-workloadselector.json"
open(path, "w").write(json.dumps(d))
subprocess.check_call(["oc", "replace", "-f", path])
print("pinned EnvoyFilter/payload-processing to maas-default-gateway workloadSelector")
PY
fi
oc set env deployment/payload-processing -n openshift-ingress \
  GATEWAY_NAME=maas-default-gateway \
  GATEWAY_NAMESPACE=openshift-ingress
oc rollout status deployment/payload-processing -n openshift-ingress --timeout=180s
oc delete pod -n openshift-ingress -l gateway.networking.k8s.io/gateway-name=maas-default-gateway --ignore-not-found
oc delete pod -n openshift-ingress -l gateway.networking.k8s.io/gateway-name=data-science-gateway --ignore-not-found
oc rollout status deployment/maas-default-gateway-openshift-default -n openshift-ingress --timeout=180s

echo ""
echo "=== Step 3: ExternalModel + MaaSModelRef (workshop model allowed by current key) ==="
# Prefer llama-31-70b-cpu manifests when present (RHOAI 3.5-ea / current workshop key).
if [ -f "$DAY5_DIR/manifests/external-model-llama-31-70b-cpu.yaml" ]; then
  oc apply -f "$DAY5_DIR/manifests/external-model-llama-31-70b-cpu.yaml"
  oc apply -f "$DAY5_DIR/manifests/maas-model-ref-llama-31-70b-cpu.yaml"
  oc apply -f "$DAY5_DIR/manifests/subscription-llama-31-70b-cpu.yaml"
  oc apply -f "$DAY5_DIR/manifests/auth-policy-llama-31-70b-cpu.yaml"
  MODEL_NAME=llama-31-70b-cpu
  SUB_NAME=llama-31-70b-cpu-free
else
  oc apply -f "$DAY5_DIR/manifests/external-model.yaml"
  oc apply -f "$DAY5_DIR/manifests/maas-model-ref.yaml"
  oc apply -f "$DAY5_DIR/manifests/subscription-patches.yaml"
  oc apply -f "$DAY5_DIR/manifests/auth-policy-patches.yaml"
  MODEL_NAME=codellama-7b-instruct
  SUB_NAME=""
fi
sleep 10

echo ""
echo "=== Step 4: Validation ==="
source "$POC_DIR/day-3/demo-env.sh" 2>/dev/null || true
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="${MAAS_URL:-https://maas.${CLUSTER_DOMAIN}}"
EXT_PATH="${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions"

# Mint a short-lived key for the external subscription when demo-env keys are absent.
if [ -z "${BASIC_USER_KEY:-}" ] && [ -n "$SUB_NAME" ]; then
  TOKEN=$(oc whoami -t)
  BASIC_USER_KEY=$($CURL -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
    -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
    -d "{\"name\":\"day5-validate\",\"expiresIn\":\"24h\",\"subscription\":\"${SUB_NAME}\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])')
fi

{
  echo "MAAS_URL=$MAAS_URL"
  echo "EXTERNAL_ENDPOINT=maas-rhdp.apps.maas.redhatworkshops.io"
  echo "MODEL=$MODEL_NAME"
  echo ""
  oc get externalmodel,maasmodelref,secret/litellm-workshop-provider-key -n llm 2>&1
  echo ""
  echo -n "model path (maas key): "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "$EXT_PATH" \
    -H "Authorization: Bearer ${BASIC_USER_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello external model\"}],\"max_tokens\":20}"
  echo -n "model path (no auth): "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "$EXT_PATH" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Ping\"}],\"max_tokens\":5}"
} | tee "$DAY5_DIR/05-validation.txt"

run_capture "06-day5-final-state.txt" sh -c '
  oc get externalmodel,maasmodelref,httproute,authpolicy,serviceentry -n llm 2>&1 | grep -i codellama || true
  oc get maassubscription simulator-free granite-tiny-gpu-premium -n models-as-a-service -o jsonpath="{range .items[*]}{.metadata.name}{\": \"}{range .spec.modelRefs[*]}{.name}{\" \"}{end}{\"\\n\"}{end}"
'

echo "=== Day 5 Installation Complete ==="
