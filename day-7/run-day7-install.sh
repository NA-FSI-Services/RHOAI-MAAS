#!/usr/bin/env bash
# Day 7 — OpenShift Lightspeed → MaaS gateway (Qwen3-4B-Instruct)
set -uo pipefail

CURL=/usr/bin/curl
DAY7_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DAY7_DIR/day7-install.log"
LIGHTSPEED_MODEL="qwen3-4b-instruct"

exec > >(tee "$LOG") 2>&1

echo "=== Day 7 Installation Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

run_capture() {
  local name="$1"; shift
  { echo "# $*"; echo "# $(date -u +"%Y-%m-%dT%H:%M:%SZ")"; echo "---"; "$@" 2>&1; } | tee "$DAY7_DIR/$name"
}

run_capture "00-state-before.txt" sh -c '
  oc get csv -n openshift-lightspeed 2>&1 | grep lightspeed || true
  oc get olsconfig -A 2>&1 || true
  oc get llminferenceservice qwen3-4b-instruct -n llm 2>&1
  oc get maasmodelref qwen3-4b-instruct -n llm 2>&1 || true
'

echo ""
echo "=== Step 1: Verify Lightspeed Operator ==="
if ! oc get csv -n openshift-lightspeed lightspeed-operator.v1.1.0 &>/dev/null; then
  CSV=$(oc get csv -n openshift-lightspeed -o name 2>/dev/null | head -1)
  echo "Lightspeed CSV: ${CSV:-NOT FOUND — install OpenShift Lightspeed Operator first}"
else
  echo "Lightspeed operator: OK"
fi

echo ""
echo "=== Step 2: Verify Qwen LLMInferenceService (tool calling pre-configured) ==="
if ! oc get llminferenceservice "${LIGHTSPEED_MODEL}" -n llm &>/dev/null; then
  echo "ERROR: ${LIGHTSPEED_MODEL} not found in llm namespace"
  exit 1
fi
QWEN_READY=$(oc get llminferenceservice "${LIGHTSPEED_MODEL}" -n llm -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
echo "Qwen Ready=${QWEN_READY:-Unknown}"
QWEN_POD=$(oc get pods -n llm -o name 2>/dev/null | grep "${LIGHTSPEED_MODEL}-kserve" | head -1)
if [ -n "$QWEN_POD" ]; then
  echo "Qwen vLLM args:"
  oc get "$QWEN_POD" -n llm -o jsonpath='{.spec.containers[?(@.name=="main")].args}{"\n"}' 2>&1
fi

echo ""
echo "=== Step 3: Register Qwen on MaaS + BBR route ==="
oc apply -f "$DAY7_DIR/manifests/qwen-maas-modelref.yaml"
oc apply -f "$DAY7_DIR/manifests/bbr-qwen-httproute.yaml"
echo "Waiting for MaaSModelRef Ready (up to 120s)..."
for i in $(seq 1 12); do
  PHASE=$(oc get maasmodelref "${LIGHTSPEED_MODEL}" -n llm -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  echo "  qwen MaaSModelRef phase=${PHASE:-Pending} (${i}0s)"
  [ "$PHASE" = "Ready" ] && break
  sleep 10
done

echo ""
echo "=== Step 4: MaaS subscription + auth for Lightspeed ==="
oc apply -f "$DAY7_DIR/manifests/demo-lightspeed-subscription.yaml"
oc apply -f "$DAY7_DIR/manifests/demo-lightspeed-auth-policy.yaml"
sleep 8

echo ""
echo "=== Step 5: Mint MaaS API key for Lightspeed ==="
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
TOKEN=$(oc whoami -t)
KEY_JSON=$($CURL -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-lightspeed-maas-key","expiresIn":"336h","subscription":"demo-openshift-lightspeed"}')
MAAS_KEY=$(echo "$KEY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null)
if [ -z "$MAAS_KEY" ]; then
  echo "ERROR: failed to mint Lightspeed MaaS key: $KEY_JSON"
  exit 1
fi
echo "MaaS key minted (prefix): ${MAAS_KEY:0:20}..."

LIGHTSPEED_ENV="$DAY7_DIR/lightspeed-maas.env"
cat > "$LIGHTSPEED_ENV" <<EOF
export MAAS_URL="${MAAS_URL}"
export LIGHTSPEED_MAAS_KEY="${MAAS_KEY}"
export LIGHTSPEED_MAAS_MODEL="${LIGHTSPEED_MODEL}"
export LIGHTSPEED_MAAS_SUB="demo-openshift-lightspeed"
EOF
chmod 600 "$LIGHTSPEED_ENV"

echo ""
echo "=== Step 6: OLS credentials secret + OLSConfig ==="
oc create secret generic maas-gateway-api-key \
  --from-literal=apitoken="${MAAS_KEY}" \
  -n openshift-lightspeed --dry-run=client -o yaml | oc apply -f -

MAAS_GATEWAY_URL="${MAAS_URL}/v1"
cat <<EOF | oc apply -f -
apiVersion: ols.openshift.io/v1alpha1
kind: OLSConfig
metadata:
  name: cluster
  labels:
    maas.opendatahub.io/day7: lightspeed-maas
spec:
  llm:
    providers:
      - name: maas-gateway
        type: openai
        url: ${MAAS_GATEWAY_URL}
        credentialsSecretRef:
          name: maas-gateway-api-key
        models:
          - name: ${LIGHTSPEED_MODEL}
            parameters:
              toolBudgetRatio: 0.5
  ols:
    defaultProvider: maas-gateway
    defaultModel: ${LIGHTSPEED_MODEL}
EOF

echo "Waiting for lightspeed-app-server (up to 300s)..."
for i in $(seq 1 30); do
  READY=$(oc get deploy lightspeed-app-server -n openshift-lightspeed -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  echo "  lightspeed-app-server ready=${READY:-0} (${i}0s)"
  [ "${READY:-0}" -ge 1 ] && break
  sleep 10
done

echo ""
echo "=== Step 7: Validation ==="
{
  echo "MAAS_URL=$MAAS_URL"
  echo "MODEL=${LIGHTSPEED_MODEL}"
  echo ""
  oc get olsconfig cluster -o jsonpath='defaultProvider={.spec.ols.defaultProvider} defaultModel={.spec.ols.defaultModel}{"\n"}' 2>&1
  oc get maasmodelref "${LIGHTSPEED_MODEL}" -n llm 2>&1
  oc get deploy lightspeed-app-server -n openshift-lightspeed 2>&1
  echo ""
  echo "--- Direct MaaS probe (same key/model Lightspeed uses) ---"
  echo -n "plain chat: "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
    -H "Authorization: Bearer ${MAAS_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${LIGHTSPEED_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":5}"
  echo -n "tool_choice auto: "
  $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
    -H "Authorization: Bearer ${MAAS_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${LIGHTSPEED_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"What is 2+2?\"}],\"max_tokens\":20,\"tool_choice\":\"auto\",\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"calculator\",\"description\":\"Add two numbers\",\"parameters\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"number\"},\"b\":{\"type\":\"number\"}},\"required\":[\"a\",\"b\"]}}}]}"
  echo ""
  echo "--- OLS API log snippet ---"
  oc logs deployment/lightspeed-app-server -n openshift-lightspeed -c lightspeed-service-api --tail=5 2>&1 || true
} | tee "$DAY7_DIR/05-validation.txt"

run_capture "06-day7-final-state.txt" sh -c '
  oc get olsconfig cluster -o yaml | head -45
  oc get maassubscription demo-openshift-lightspeed -n models-as-a-service
  oc get maasmodelref qwen3-4b-instruct -n llm
  oc get httproute bbr-qwen3-4b-instruct -n llm
  oc get pods -n openshift-lightspeed
'

echo "=== Day 7 Installation Complete ==="
echo "Keys: $LIGHTSPEED_ENV (gitignored)"
echo "Optional demo: OpenShift Console → Lightspeed icon → ask a cluster question"
