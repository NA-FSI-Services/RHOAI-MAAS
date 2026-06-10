#!/usr/bin/env bash
# Deploy community Grafana operator + MaaS token usage dashboard (tokens per user/model).
set -euo pipefail

DAY6_DIR="$(cd "$(dirname "$0")" && pwd)"
NS=maas-grafana
JSON_ONLY=false

usage() {
  cat <<'EOF'
Usage: ./apply-grafana-dashboard.sh [--json-only]

  default   Install Grafana operator (if needed), Grafana instance, Prometheus
            datasource, and the MaaS Token Usage dashboard.
  --json-only
            Print manual import instructions for day-6/dashboards/maas-token-usage.json
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json-only) JSON_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [ "$JSON_ONLY" = true ]; then
  echo "Import dashboard JSON manually:"
  echo "  file: ${DAY6_DIR}/dashboards/maas-token-usage.json"
  echo "  datasource uid: maas-prometheus (platform Thanos querier)"
  echo "  metrics: authorized_hits{user,model,subscription,cost_center}"
  exit 0
fi

command -v oc >/dev/null || { echo "oc not found in PATH" >&2; exit 1; }

echo "=== Applying Grafana manifests ==="
oc apply -k "${DAY6_DIR}/manifests/grafana/"

oc create configmap maas-token-usage-dashboard \
  -n "$NS" \
  --from-file=maas-token-usage.json="${DAY6_DIR}/dashboards/maas-token-usage.json" \
  --dry-run=client -o yaml | oc apply -f -
oc label configmap maas-token-usage-dashboard -n "$NS" \
  app.kubernetes.io/part-of=maas-observability \
  maas.opendatahub.io/day6=observability-demo --overwrite

echo "=== Waiting for Grafana operator CSV (up to 300s) ==="
for i in $(seq 1 30); do
  PHASE=$(oc get csv -n "$NS" --no-headers 2>/dev/null | awk '{print $NF}' | head -1 || true)
  echo "  grafana-operator CSV=${PHASE:-pending} (${i}0s)"
  [ "$PHASE" = "Succeeded" ] && break
  sleep 10
done

ADMIN_PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
oc create secret generic maas-grafana-admin \
  -n "$NS" \
  --from-literal=GF_SECURITY_ADMIN_PASSWORD="${ADMIN_PASS}" \
  --dry-run=client -o yaml | oc apply -f -

PROM_TOKEN=$(oc create token maas-grafana-thanos-reader -n "$NS" --duration=8760h)
oc create secret generic maas-grafana-prometheus-token \
  -n "$NS" \
  --from-literal=authorization="Bearer ${PROM_TOKEN}" \
  --dry-run=client -o yaml | oc apply -f -

echo "=== Waiting for Grafana route (up to 180s) ==="
for i in $(seq 1 18); do
  HOST=$(oc get route maas-grafana -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  [ -n "$HOST" ] && break
  sleep 10
done

if [ -z "$HOST" ]; then
  HOST=$(oc get route -n "$NS" -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
fi

echo ""
echo "=== MaaS Grafana dashboard deployed ==="
echo "Dashboard JSON : ${DAY6_DIR}/dashboards/maas-token-usage.json"
echo "Grafana route  : ${HOST:-<pending>}"
echo "Login user     : admin"
echo "Login password : ${ADMIN_PASS}"
echo ""
echo "Seed metrics if charts are empty:"
echo "  ./day-6/daily-traffic.sh --quick"
echo ""
oc get grafanadashboard,grafanadatasource,grafana -n "$NS" 2>/dev/null || true
