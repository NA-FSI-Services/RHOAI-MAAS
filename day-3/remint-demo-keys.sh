#!/usr/bin/env bash
# Remint Day 3 tier keys for Demo 2 auth scenarios (401/403/200).
set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${POC_DIR}/day-3/demo-env.sh"
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
TOKEN=$(oc whoami -t)

mint() {
  local name=$1 sub=$2
  curl -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"expiresIn\":\"336h\",\"subscription\":\"${sub}\"}"
}

BASIC_JSON=$(mint "demo-basic-key" "simulator-free")
ADV_JSON=$(mint "demo-advanced-key" "granite-tiny-gpu-premium")
BASIC_KEY=$(python3 -c "import json,sys; print(json.load(sys.stdin)['key'])" <<<"$BASIC_JSON")
ADV_KEY=$(python3 -c "import json,sys; print(json.load(sys.stdin)['key'])" <<<"$ADV_JSON")

cat > "$OUT" <<EOF
export MAAS_URL="${MAAS_URL}"
export BASIC_USER_KEY="${BASIC_KEY}"
export ADVANCED_USER_KEY="${ADV_KEY}"
EOF

echo "Wrote ${OUT}"
echo "  BASIC_USER_KEY  → subscription simulator-free (simulator 200, granite 403)"
echo "  ADVANCED_USER_KEY → subscription granite-tiny-gpu-premium (CodeLlama only after Day 6; use DEMO_RISK_KEY for Granite Scenario D)"
echo ""
echo "Run: source day-3/demo-env.sh"
