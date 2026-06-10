#!/usr/bin/env bash
# Day 6 — Cluster Observability Operator + demo personas for showback dashboards
set -uo pipefail

CURL=/usr/bin/curl
DAY6_DIR="$(cd "$(dirname "$0")" && pwd)"
POC_DIR="$(cd "$DAY6_DIR/.." && pwd)"
GUIDE="$POC_DIR/work/rhoai-maas-guide"
LOG="$DAY6_DIR/day6-install.log"

exec > >(tee "$LOG") 2>&1

echo "=== Day 6 Installation Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

run_capture() {
  local name="$1"; shift
  { echo "# $*"; echo "# $(date -u +"%Y-%m-%dT%H:%M:%SZ")"; echo "---"; "$@" 2>&1; } | tee "$DAY6_DIR/$name"
}

run_capture "00-state-before.txt" sh -c '
  oc get csv -n openshift-cluster-observability-operator 2>&1 || true
  oc get persesdashboard -A 2>&1 || true
  oc get maassubscription -n models-as-a-service 2>&1
'

echo ""
echo "=== Step 1: Install Cluster Observability Operator (COO) ==="
oc apply -k "$GUIDE/manifests/07-observability/coo/"
echo "Waiting for COO CSV (up to 600s)..."
for i in $(seq 1 60); do
  PHASE=$(oc get csv -n openshift-cluster-observability-operator --no-headers 2>/dev/null \
    | grep cluster-observability | awk "{print \$NF}" || echo "")
  echo "  COO phase=${PHASE:-pending} (${i}0s)"
  [ "$PHASE" = "Succeeded" ] && break
  sleep 10
done

echo ""
echo "=== Step 1b: RHOAI observability stack (DSCInitialization metrics + OpenTelemetry) ==="
oc apply -f "$DAY6_DIR/manifests/dsci-metrics-storage.yaml"
oc apply -f "$DAY6_DIR/manifests/opentelemetry-operator/subscription.yaml"
echo "Waiting for OpenTelemetry operator CSV (up to 300s)..."
for i in $(seq 1 30); do
  OTEL=$(oc get csv -n openshift-opentelemetry-operator --no-headers 2>/dev/null | awk '{print $NF}' | head -1)
  echo "  OpenTelemetry CSV=${OTEL:-pending} (${i}0s)"
  [ "$OTEL" = "Succeeded" ] && break
  sleep 10
done
echo "Waiting for Perses backend (up to 600s)..."
for i in $(seq 1 60); do
  PERSES=$(oc get monitoring default-monitoring -o jsonpath='{.status.conditions[?(@.type=="PersesAvailable")].status}' 2>/dev/null || echo "")
  PODS=$(oc get pods -n redhat-ods-monitoring --no-headers 2>/dev/null | grep -c Running || echo 0)
  echo "  PersesAvailable=${PERSES:-?} running_pods=${PODS} (${i}0s)"
  [ "$PERSES" = "True" ] && [ "$PODS" -ge 3 ] && break
  sleep 10
done
chmod +x "$DAY6_DIR/fix-perses-datasource-secret.sh"
"$DAY6_DIR/fix-perses-datasource-secret.sh"

echo ""
echo "=== Step 2: Gateway telemetry + Observability UI flag ==="
oc apply -k "$GUIDE/manifests/07-observability/telemetry/"
oc apply -f "$DAY6_DIR/manifests/telemetry-policy.yaml"
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge \
  -p "{\"spec\":{\"dashboardConfig\":{\"observabilityDashboard\":true}}}" 2>/dev/null || true
sleep 15

echo ""
echo "=== Step 3: Demo subscriptions + auth policies + persona RBAC ==="
oc apply -f "$DAY6_DIR/manifests/demo-subscriptions.yaml"
oc apply -f "$DAY6_DIR/manifests/demo-auth-policies.yaml"
oc apply -f "$DAY6_DIR/manifests/demo-restrict-default-granite.yaml"
oc delete maassubscription granite-tiny-gpu-free -n models-as-a-service --ignore-not-found
oc apply -f "$DAY6_DIR/manifests/demo-maas-api-rbac.yaml"
sleep 10

echo ""
echo "=== Step 4: Mint per-persona API keys (as htpasswd users) ==="
chmod +x "$DAY6_DIR/mint-persona-keys.sh"
if [ -f "$POC_DIR/day-1/demo-users-passwords.env" ]; then
  "$DAY6_DIR/mint-persona-keys.sh"
else
  echo "[WARN] day-1/demo-users-passwords.env missing — run day-1/setup-multi-user.sh first"
  echo "       Falling back to admin token (all keys will show user=admin in metrics)"
  source "$POC_DIR/day-3/demo-env.sh" 2>/dev/null || true
  CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
  MAAS_URL="${MAAS_URL:-https://maas.${CLUSTER_DOMAIN}}"
  TOKEN=$(oc whoami -t)
  USERS_ENV="$DAY6_DIR/demo-users.env"
  mint() {
    local name="$1" sub="$2"
    $CURL -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${name}\",\"expiresIn\":\"336h\",\"subscription\":\"${sub}\"}"
  }
  RETAIL_JSON=$(mint "demo-retail-analyst-key" "demo-retail-analyst")
  RISK_JSON=$(mint "demo-risk-analytics-key" "demo-risk-analytics")
  PLATFORM_JSON=$(mint "demo-platform-ops-key" "demo-platform-ops")
  python3 - "$USERS_ENV" "$MAAS_URL" "$RETAIL_JSON" "$RISK_JSON" "$PLATFORM_JSON" <<'PY'
import json, sys
out, maas, *payloads = sys.argv[1:6]
retail, risk, platform = [json.loads(p) for p in payloads]
lines = [
    f'export MAAS_URL="{maas}"',
    f'export DEMO_RETAIL_KEY="{retail.get("key", "")}"',
    f'export DEMO_RISK_KEY="{risk.get("key", "")}"',
    f'export DEMO_PLATFORM_KEY="{platform.get("key", "")}"',
    "export DEMO_RETAIL_SUB=demo-retail-analyst",
    "export DEMO_RISK_SUB=demo-risk-analytics",
    "export DEMO_PLATFORM_SUB=demo-platform-ops",
]
open(out, "w").write("\n".join(lines) + "\n")
print("Wrote", out)
PY
  chmod 600 "$USERS_ENV"
fi

echo ""
echo "=== Step 5: Initial traffic seed ==="
"$DAY6_DIR/daily-traffic.sh" --quick

echo ""
echo "=== Step 6: Validation ==="
{
  echo "MAAS_URL=$MAAS_URL"
  oc get csv -n openshift-cluster-observability-operator 2>&1 | grep cluster-observability || true
  oc get csv -n openshift-opentelemetry-operator 2>&1 | grep opentelemetry || true
  oc get monitoring default-monitoring -o jsonpath='PersesAvailable={.status.conditions[?(@.type=="PersesAvailable")].status}{"\n"}' 2>&1
  oc get pods -n redhat-ods-monitoring 2>&1
  oc get secret kuadrant-prometheus-datasource-secret -n redhat-ods-applications 2>&1
  oc get persesdashboard -n redhat-ods-applications 2>&1
  oc get maassubscription -n models-as-a-service -l maas.opendatahub.io/day6=observability-demo
  oc get telemetrypolicy -n openshift-ingress maas-telemetry -o jsonpath='{.status.conditions[?(@.type=="Enforced")].status}{"\n"}' 2>&1
} | tee "$DAY6_DIR/05-validation.txt"

run_capture "06-day6-final-state.txt" sh -c '
  oc get perses,persesdashboard,persesdatasource -A 2>&1 | head -20
  oc get maassubscription demo-retail-analyst demo-risk-analytics demo-platform-ops -n models-as-a-service
'

echo "=== Day 6 Installation Complete ==="
echo "Next: run ./day-6/daily-traffic.sh daily until demo day (see README.md)."
