#!/usr/bin/env bash
# Day 7 — OpenShift Lightspeed → MaaS gateway (local Llama 3.1 8B Instruct)
set -uo pipefail

CURL=/usr/bin/curl
DAY7_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DAY7_DIR/day7-install.log"
LIGHTSPEED_MODEL="llama-3-1-8b-instruct"

exec > >(tee "$LOG") 2>&1

echo "=== Day 7 Installation Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

run_capture() {
  local name="$1"; shift
  { echo "# $*"; echo "# $(date -u +"%Y-%m-%dT%H:%M:%SZ")"; echo "---"; "$@" 2>&1; } | tee "$DAY7_DIR/$name"
}

run_capture "00-state-before.txt" sh -c '
  oc get csv -n openshift-lightspeed 2>&1 | grep lightspeed || true
  oc get olsconfig -A 2>&1 || true
  oc get llminferenceservice llama-3-1-8b-instruct -n llm 2>&1
  oc get maasmodelref llama-3-1-8b-instruct -n llm 2>&1 || true
'

echo ""
echo "=== Step 1: Install / verify Lightspeed Operator ==="
oc apply -f "$DAY7_DIR/manifests/lightspeed-operator-subscription.yaml"
echo "Waiting for Lightspeed CSV Succeeded (up to 600s)..."
for i in $(seq 1 60); do
  PHASE=$(oc get csv -n openshift-lightspeed -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null \
    | awk '/lightspeed-operator/{print $2; exit}')
  echo "  Lightspeed CSV phase=${PHASE:-pending} (${i}0s)"
  [ "$PHASE" = "Succeeded" ] && break
  sleep 10
done
if [ "${PHASE:-}" != "Succeeded" ]; then
  echo "ERROR: Lightspeed operator did not become Succeeded"
  oc get csv -n openshift-lightspeed 2>&1 || true
  exit 1
fi

echo ""
echo "=== Step 2: Enable tool calling on local Llama (Lightspeed requires tool_choice=auto) ==="
if ! oc get llminferenceservice "${LIGHTSPEED_MODEL}" -n llm &>/dev/null; then
  echo "ERROR: ${LIGHTSPEED_MODEL} not found in llm namespace"
  exit 1
fi

# Merge tool-calling args + 32k context (Lightspeed MCP tools overflow 8k)
oc get llminferenceservice "${LIGHTSPEED_MODEL}" -n llm -o json > /tmp/llmis-lightspeed.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/llmis-lightspeed.json"))
containers=d["spec"]["template"]["containers"]
args=list(containers[0].get("args") or [])
# bump context for OLS system+RAG+MCP tool schemas
args=[a for a in args if not a.startswith("--max-model-len=")]
args.append("--max-model-len=32768")
for a in ["--enable-auto-tool-choice", "--tool-call-parser=llama3_json"]:
    if a not in args:
        args.append(a)
containers[0]["args"]=args
open("/tmp/llama-tool-merge.json","w").write(json.dumps({"spec":{"template":{"containers":containers}}}))
print("args=", args)
PY
oc patch llminferenceservice "${LIGHTSPEED_MODEL}" -n llm --type=merge --patch-file=/tmp/llama-tool-merge.json

echo "Waiting for Llama LLMInferenceService Ready (up to 900s)..."
for i in $(seq 1 90); do
  READY=$(oc get llminferenceservice "${LIGHTSPEED_MODEL}" -n llm -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  POD=$(oc get pods -n llm --no-headers 2>/dev/null | awk '/llama-3-1-8b-instruct-kserve/ && !/Terminating/{print $1":"$2":"$3; exit}')
  echo "  Ready=${READY:-?} pod=${POD:-none} (${i}0s)"
  [ "$READY" = "True" ] && break
  sleep 10
done
READY=$(oc get llminferenceservice "${LIGHTSPEED_MODEL}" -n llm -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [ "$READY" != "True" ]; then
  echo "ERROR: ${LIGHTSPEED_MODEL} not Ready after tool-calling patch"
  exit 1
fi
POD=$(oc get pods -n llm --no-headers | awk '/llama-3-1-8b-instruct-kserve/ && /Running/{print $1; exit}')
echo "Llama vLLM args:"
oc get pod -n llm "$POD" -o jsonpath='{.spec.containers[?(@.name=="main")].args}{"\n"}' 2>&1

echo ""
echo "=== Step 3: BBR route for unified /v1 (model already on MaaS) ==="
oc apply -f "$DAY7_DIR/manifests/bbr-llama-httproute.yaml"
oc get maasmodelref "${LIGHTSPEED_MODEL}" -n llm

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

# Prefer model-specific OpenAI base URL (reliable); BBR /v1 also wired above.
MAAS_GATEWAY_URL="${MAAS_URL}/llm/${LIGHTSPEED_MODEL}/v1"
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
            contextWindowSize: 32768
            parameters:
              toolBudgetRatio: 0.35
              maxTokensForResponse: 1024
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
  echo "OLS_URL=${MAAS_GATEWAY_URL}"
  echo ""
  oc get olsconfig cluster -o jsonpath='defaultProvider={.spec.ols.defaultProvider} defaultModel={.spec.ols.defaultModel}{"\n"}' 2>&1
  oc get maasmodelref "${LIGHTSPEED_MODEL}" -n llm 2>&1
  oc get deploy lightspeed-app-server -n openshift-lightspeed 2>&1
  echo ""
  echo "--- Direct MaaS probe (same key/model Lightspeed uses) ---"
  echo -n "plain chat: "
  $CURL -sk -o /dev/null -w "HTTP %{http_code}\n" -X POST "${MAAS_URL}/llm/${LIGHTSPEED_MODEL}/v1/chat/completions" \
    -H "Authorization: Bearer ${MAAS_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${LIGHTSPEED_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":5}"
  echo -n "tool_choice auto: "
  $CURL -sk -o /tmp/ls-tool.json -w "HTTP %{http_code}\n" -X POST "${MAAS_URL}/llm/${LIGHTSPEED_MODEL}/v1/chat/completions" \
    -H "Authorization: Bearer ${MAAS_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${LIGHTSPEED_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"What is 2+2?\"}],\"max_tokens\":20,\"tool_choice\":\"auto\",\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"calculator\",\"description\":\"Add two numbers\",\"parameters\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"number\"},\"b\":{\"type\":\"number\"}},\"required\":[\"a\",\"b\"]}}}]}"
  head -c 200 /tmp/ls-tool.json; echo
  echo ""
  echo "--- OLS API log snippet ---"
  oc logs deployment/lightspeed-app-server -n openshift-lightspeed -c lightspeed-service-api --tail=8 2>&1 || true
} | tee "$DAY7_DIR/05-validation.txt"

run_capture "06-day7-final-state.txt" sh -c '
  oc get olsconfig cluster -o yaml | head -50
  oc get maassubscription demo-openshift-lightspeed -n models-as-a-service
  oc get httproute bbr-llama-3-1-8b-instruct -n llm
  oc get pods -n openshift-lightspeed
'

echo "=== Day 7 Installation Complete ==="
echo "Keys: $LIGHTSPEED_ENV (gitignored)"
echo "Console: OpenShift → Lightspeed icon → ask a cluster question (uses ${LIGHTSPEED_MODEL} via MaaS)"
