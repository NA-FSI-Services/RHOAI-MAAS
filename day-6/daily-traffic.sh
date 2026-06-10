#!/usr/bin/env bash
# Generate per-user demo traffic for MaaS observability dashboards.
# Run once daily from Day 6 through demo day (~09:00 local recommended).
#
# Usage:
#   ./day-6/daily-traffic.sh           # full daily seed
#   ./day-6/daily-traffic.sh --quick   # lighter burst
#   ./day-6/daily-traffic.sh --cron    # append to ~/maas-demo-traffic.log (for cron)
set -uo pipefail

CURL=/usr/bin/curl
DAY6_DIR="$(cd "$(dirname "$0")" && pwd)"
POC_DIR="$(cd "$DAY6_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$POC_DIR/day-3/demo-env.sh"
# shellcheck disable=SC1091
source "$DAY6_DIR/demo-users.env"

QUICK=false
CRON=false
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=true ;;
    --cron) CRON=true ;;
  esac
done

log() {
  if $CRON; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "${HOME}/maas-demo-traffic.log"
  else
    echo "$*"
  fi
}

run_chat() {
  local label="$1" url="$2" key="$3" model="$4" content="$5" max_tokens="$6"
  local code
  code=$($CURL -m 120 -si -o /dev/null -w "%{http_code}" -X POST "$url" \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":${content}}],\"max_tokens\":${max_tokens}}")
  log "  ${label}: HTTP ${code}"
}

SIM="${MAAS_URL}/llm/facebook-opt-125m-simulated/v1/chat/completions"
GRAN="${MAAS_URL}/llm/granite-4-tiny-gpu/v1/chat/completions"
EXT="${MAAS_URL}/llm/codellama-7b-instruct/v1/chat/completions"

log "=== Daily observability traffic ==="
log "MAAS_URL=${MAAS_URL}"

if $QUICK; then
  LOOPS=1
  GRAN_TOK=25
else
  LOOPS=3
  GRAN_TOK=50
fi

log "--- Retail analyst (${DEMO_RETAIL_SUB}) — low volume ---"
for i in $(seq 1 "$LOOPS"); do
  run_chat "retail-sim-${i}" "$SIM" "$DEMO_RETAIL_KEY" "facebook/opt-125m" \
    "\"Retail compliance checklist item ${i} for branch audit.\"" 35
  run_chat "retail-ext-${i}" "$EXT" "$DEMO_RETAIL_KEY" "codellama-7b-instruct" \
    "\"Summarize KYC requirements (${i}).\"" 30
done

log "--- Risk analytics (${DEMO_RISK_SUB}) — high Granite volume ---"
for i in $(seq 1 "$LOOPS"); do
  run_chat "risk-granite-${i}" "$GRAN" "$DEMO_RISK_KEY" "granite-4-tiny-gpu" \
    "\"Analyze credit risk exposure and capital adequacy for portfolio scenario ${i}. Include PD, LGD, and EAD factors.\"" \
    "$GRAN_TOK"
  run_chat "risk-ext-${i}" "$EXT" "$DEMO_RISK_KEY" "codellama-7b-instruct" \
    "\"Draft risk committee memo section ${i}.\"" 40
done

log "--- Platform ops (${DEMO_PLATFORM_SUB}) — cross-model ---"
for i in $(seq 1 "$LOOPS"); do
  run_chat "platform-sim-${i}" "$SIM" "$DEMO_PLATFORM_KEY" "facebook/opt-125m" \
    "\"Platform health check ${i}.\"" 20
  run_chat "platform-granite-${i}" "$GRAN" "$DEMO_PLATFORM_KEY" "granite-4-tiny-gpu" \
    "\"Gateway routing validation ${i}.\"" 30
  run_chat "platform-ext-${i}" "$EXT" "$DEMO_PLATFORM_KEY" "codellama-7b-instruct" \
    "\"External model smoke test ${i}.\"" 25
done

log "Done — check RHOAI Console → Observe & monitor → Observability"
