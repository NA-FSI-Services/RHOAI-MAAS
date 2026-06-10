#!/usr/bin/env bash
# Day 3 — Gateway fix, API keys, auth validation, observability, verification
set -uo pipefail

CURL=/usr/bin/curl
GUIDE_DIR="$(cd "$(dirname "$0")/../work/rhoai-maas-guide" && pwd)"
OUT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$OUT_DIR/day3-install.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

exec > >(tee "$LOG") 2>&1

echo "=== Day 3 Installation Started: $TIMESTAMP ==="

run_capture() {
  local name="$1"; shift
  { echo "# $*"; echo "# $(date -u +"%Y-%m-%dT%H:%M:%SZ")"; echo "---"; "$@" 2>&1; } | tee "$OUT_DIR/$name"
}

# Snapshot before
run_capture "00-state-before.txt" sh -c '
  oc get authorino authorino -n kuadrant-system -o jsonpath="Ready={.status.conditions[?(@.type==\"Ready\")].status} msg={.status.conditions[?(@.type==\"Ready\")].message}{\"\n\"}"
  oc get secret authorino-server-cert -n kuadrant-system 2>&1 || true
  oc get deploy maas-api -n maas-api -o custom-columns=NS:.metadata.namespace,READY:.status.readyReplicas 2>&1
  CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath="{.spec.domain}")
  MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
  echo "MAAS_URL=$MAAS_URL"
  echo -n "GET /v1/models: "; curl -sk -o /dev/null -w "HTTP %{http_code}\n" "${MAAS_URL}/v1/models"
'

# Step 1: Authorino TLS fix
echo ""
echo "=== Step 1: Authorino TLS (service-annotation.yaml) ==="
oc apply -f "$GUIDE_DIR/manifests/02-platform-config/kuadrant/service-annotation.yaml"
for i in $(seq 1 24); do
  oc get secret authorino-server-cert -n kuadrant-system &>/dev/null && break
  sleep 5
done
oc patch authorino authorino -n kuadrant-system --type=merge --patch '{
  "spec": {"listener": {"tls": {"enabled": true, "certSecretRef": {"name": "authorino-server-cert"}}}}
}'
oc -n kuadrant-system set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt
oc rollout restart deployment/authorino -n kuadrant-system
oc rollout status deployment/authorino -n kuadrant-system --timeout=120s

# Step 2: Legacy maas-api cleanup
echo ""
echo "=== Step 2: Legacy maas-api cleanup ==="
oc scale deployment maas-api -n maas-api --replicas=0 2>/dev/null || true
oc delete httproute maas-api-route -n maas-api 2>/dev/null || true
oc delete authpolicy maas-api-auth-policy -n maas-api 2>/dev/null || true

# Step 3: Kuadrant restart
echo ""
echo "=== Step 3: Kuadrant operator restart ==="
oc delete pod -n openshift-operators -l app.kubernetes.io/name=kuadrant-operator-controller-manager 2>/dev/null || true
sleep 15

# Step 4: Gateway smoke
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
{
  echo "MAAS_URL=$MAAS_URL"
  for path in /maas-api/health /v1/models /llm/granite-4-tiny-gpu/v1/models; do
    echo -n "GET ${path}: "; $CURL -sk -o /dev/null -w "HTTP %{http_code}\n" "${MAAS_URL}${path}"
  done
} | tee "$OUT_DIR/04-gateway-smoke.txt"

# Step 5: API keys
echo ""
echo "=== Step 5: Mint demo API keys ==="
TOKEN=$(oc whoami -t)
BASIC_RESP=$($CURL -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"demo-basic-key","expiresIn":"48h","subscription":"simulator-free"}')
ADV_RESP=$($CURL -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"demo-advanced-key","expiresIn":"48h","subscription":"granite-tiny-gpu-premium"}')
BASIC_KEY=$(echo "$BASIC_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null)
ADV_KEY=$(echo "$ADV_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null)
{
  echo "export MAAS_URL=\"${MAAS_URL}\""
  echo "export BASIC_USER_KEY=\"${BASIC_KEY}\""
  echo "export ADVANCED_USER_KEY=\"${ADV_KEY}\""
} > "$OUT_DIR/demo-env.sh"
echo "Keys saved to demo-env.sh (not committed — local demo use only)"

# Step 6: Auth flows
echo ""
echo "=== Step 6: Auth flow validation ==="
SIM_URL="${MAAS_URL}/llm/facebook-opt-125m-simulated"
GRAN_URL="${MAAS_URL}/llm/granite-4-tiny-gpu"
{
  echo "A) No auth:"; $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${SIM_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Ping"}],"max_tokens":5}'
  echo "B) Basic + simulator:"; $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${SIM_URL}/v1/chat/completions" \
    -H "Authorization: Bearer ${BASIC_KEY}" -H "Content-Type: application/json" \
    -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Hello"}],"max_tokens":15}'
  echo "C) Basic + granite:"; $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${GRAN_URL}/v1/chat/completions" \
    -H "Authorization: Bearer ${BASIC_KEY}" -H "Content-Type: application/json" \
    -d '{"model":"granite-4-tiny-gpu","messages":[{"role":"user","content":"Hello"}],"max_tokens":10}'
  echo "D) Advanced + granite:"; $CURL -si -o /dev/null -w "HTTP %{http_code}\n" -X POST "${GRAN_URL}/v1/chat/completions" \
    -H "Authorization: Bearer ${ADV_KEY}" -H "Content-Type: application/json" \
    -d '{"model":"granite-4-tiny-gpu","messages":[{"role":"user","content":"Summarize MaaS."}],"max_tokens":30}'
} | tee "$OUT_DIR/05-auth-flows.txt"

# Step 7: Observability
echo ""
echo "=== Step 7: Observability dashboard ==="
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge \
  -p '{"spec":{"dashboardConfig":{"observabilityDashboard":true}}}' 2>/dev/null || true

# Step 8: verify-maas.sh
echo ""
echo "=== Step 8: verify-maas.sh ==="
cd "$GUIDE_DIR"
./scripts/verify-maas.sh --no-cleanup 2>&1 | tee "$OUT_DIR/07-verify-and-rate-limit.log"

# Final state
run_capture "08-day3-final-state.txt" sh -c "
  oc get authorino authorino -n kuadrant-system -o jsonpath='Ready={.status.conditions[?(@.type==\"Ready\")].status}{\"\n\"}'
  oc get maasmodelref,maassubscription -A
  oc get llminferenceservice -n llm
"

echo "=== Day 3 Installation Complete ==="
