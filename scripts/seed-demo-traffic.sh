#!/usr/bin/env bash
# Seed MaaS gateway traffic for observability / showback demos (Demo 6).
# Prefer day-6/daily-traffic.sh for per-user personas after Day 6 install.
# Run once 24–48h before demo and again ~30 min before presenting.
#
# Usage:
#   source day-3/demo-env.sh
#   ./scripts/seed-demo-traffic.sh
#   ./scripts/seed-demo-traffic.sh --quick    # smaller burst
set -uo pipefail

CURL=/usr/bin/curl
POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck disable=SC1091
source "$POC_DIR/day-3/demo-env.sh"

: "${MAAS_URL:?source day-3/demo-env.sh first}"
: "${BASIC_USER_KEY:?}"
: "${ADVANCED_USER_KEY:?}"

QUICK=false
[ "${1:-}" = "--quick" ] && QUICK=true

SIM="${MAAS_URL}/llm/facebook-opt-125m-simulated/v1/chat/completions"
GRAN="${MAAS_URL}/llm/granite-4-tiny-gpu/v1/chat/completions"
EXT="${MAAS_URL}/llm/codellama-7b-instruct/v1/chat/completions"
UNIFIED="${MAAS_URL}/v1/chat/completions"

run_chat() {
  local label="$1" url="$2" key="$3" model="$4" content="$5" max_tokens="$6"
  local code
  code=$($CURL -m 120 -si -o /dev/null -w "%{http_code}" -X POST "$url" \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":${content}}],\"max_tokens\":${max_tokens}}")
  echo "  ${label}: HTTP ${code}"
}

echo "=== Seeding demo traffic $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "MAAS_URL=${MAAS_URL}"
echo ""

if $QUICK; then
  LOOPS=2
  GRANITE_TOKENS=30
else
  LOOPS=5
  GRANITE_TOKENS=60
fi

echo "--- Basic tier (simulator + external) ---"
for i in $(seq 1 "$LOOPS"); do
  run_chat "simulator-${i}" "$SIM" "$BASIC_USER_KEY" "facebook/opt-125m" \
    "\"Summarize retail banking compliance topic ${i} in two sentences.\"" 40
  run_chat "external-${i}" "$EXT" "$BASIC_USER_KEY" "codellama-7b-instruct" \
    "\"What is model governance? (request ${i})\"" 35
done

echo ""
echo "--- Advanced tier (Granite — token-heavy for TPM charts) ---"
for i in $(seq 1 "$LOOPS"); do
  run_chat "granite-${i}" "$GRAN" "$ADVANCED_USER_KEY" "granite-4-tiny-gpu" \
    "\"Explain credit risk modeling, capital adequacy, and stress testing for scenario ${i}. Be concise but substantive.\"" \
    "$GRANITE_TOKENS"
done

echo ""
echo "--- Unified BBR (local models only) ---"
for i in 1 2; do
  run_chat "bbr-sim-${i}" "$UNIFIED" "$BASIC_USER_KEY" "facebook/opt-125m" \
    "\"Quick ping ${i}\"" 15
  run_chat "bbr-granite-${i}" "$UNIFIED" "$ADVANCED_USER_KEY" "granite-4-tiny-gpu" \
    "\"Unified routing check ${i}\"" 25
done

echo ""
echo "Done. Open RHOAI Console → Observe & monitor → Observability."
echo "Re-run on demo morning for fresh time-series data."
