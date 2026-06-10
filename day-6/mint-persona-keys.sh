#!/usr/bin/env bash
# Mint per-persona MaaS API keys as each htpasswd user (not cluster-admin).
# Requires day-1/setup-multi-user.sh and persona groups/subscriptions applied.
set -uo pipefail

CURL=/usr/bin/curl
DAY6_DIR="$(cd "$(dirname "$0")" && pwd)"
POC_DIR="$(cd "$DAY6_DIR/.." && pwd)"
USERS_ENV="$DAY6_DIR/demo-users.env"
PASS_ENV="$POC_DIR/day-1/demo-users-passwords.env"

if [ ! -f "$PASS_ENV" ]; then
  echo "Missing $PASS_ENV — run day-1/setup-multi-user.sh first (copy from .example)"
  exit 1
fi

# shellcheck disable=SC1090
source "$PASS_ENV"

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="${MAAS_URL:-https://maas.${CLUSTER_DOMAIN}}"
SERVER=$(oc whoami --show-server 2>/dev/null || echo "https://api.${CLUSTER_DOMAIN}:6443")
ADMIN_TOKEN=$(oc whoami -t 2>/dev/null || true)

mint_as_user() {
  local oc_user="$1" oc_pass="$2" key_name="$3" sub="$4"
  echo "Minting ${key_name} as ${oc_user} (subscription=${sub})..." >&2
  if ! oc login -u "$oc_user" -p "$oc_pass" --server="$SERVER" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "[ERROR] oc login failed for $oc_user" >&2
    return 1
  fi
  local token
  token=$(oc whoami -t)
  echo "  logged in: $(oc whoami)" >&2
  $CURL -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${key_name}\",\"expiresIn\":\"336h\",\"subscription\":\"${sub}\"}"
}

echo "=== Mint persona API keys: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
echo "MAAS_URL=$MAAS_URL"

RETAIL_JSON=$(mint_as_user "$HT_USER_RETAIL" "$HT_PASS_RETAIL" "demo-retail-analyst-key" "demo-retail-analyst")
RISK_JSON=$(mint_as_user "$HT_USER_RISK" "$HT_PASS_RISK" "demo-risk-analytics-key" "demo-risk-analytics")
PLATFORM_JSON=$(mint_as_user "$HT_USER_PLATFORM" "$HT_PASS_PLATFORM" "demo-platform-ops-key" "demo-platform-ops")

if [ -n "$ADMIN_TOKEN" ]; then
  oc login --token="$ADMIN_TOKEN" --server="$SERVER" --insecure-skip-tls-verify=true >/dev/null 2>&1 || true
  echo "Restored admin session"
fi

python3 - "$USERS_ENV" "$MAAS_URL" "$RETAIL_JSON" "$RISK_JSON" "$PLATFORM_JSON" <<'PY'
import json, sys
out, maas, *payloads = sys.argv[1:6]
retail, risk, platform = [json.loads(p) for p in payloads]
for label, data in [("retail", retail), ("risk", risk), ("platform", platform)]:
    if not data.get("key"):
        print(f"[WARN] No key in response for {label}: {data}", file=sys.stderr)
lines = [
    f'export MAAS_URL="{maas}"',
    f'export DEMO_RETAIL_KEY="{retail.get("key", "")}"',
    f'export DEMO_RISK_KEY="{risk.get("key", "")}"',
    f'export DEMO_PLATFORM_KEY="{platform.get("key", "")}"',
    "export DEMO_RETAIL_SUB=demo-retail-analyst",
    "export DEMO_RISK_SUB=demo-risk-analytics",
    "export DEMO_PLATFORM_SUB=demo-platform-ops",
    f'export HT_USER_RETAIL="{retail.get("username", "demo-retail-analyst")}"',
    'export HT_USER_RISK="demo-risk-analyst"',
    'export HT_USER_PLATFORM="demo-platform-ops"',
]
open(out, "w").write("\n".join(lines) + "\n")
print("Wrote", out)
PY
chmod 600 "$USERS_ENV"
echo "=== Key minting complete ==="
