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

# Live catalog on this cluster (override via env if a lab still uses Granite/CodeLlama).
SIM_SLUG="${TRAFFIC_SIM_SLUG:-facebook-opt-125m-simulated}"
SIM_MODEL="${TRAFFIC_SIM_MODEL:-facebook/opt-125m}"
GPU_SLUG="${TRAFFIC_GPU_SLUG:-llama-3-1-8b-instruct}"
GPU_MODEL="${TRAFFIC_GPU_MODEL:-llama-3-1-8b-instruct}"
EXT_SLUG="${TRAFFIC_EXT_SLUG:-llama-31-70b-cpu}"
EXT_MODEL="${TRAFFIC_EXT_MODEL:-llama-31-70b-cpu}"

SIM="${MAAS_URL}/llm/${SIM_SLUG}/v1/chat/completions"
GPU="${MAAS_URL}/llm/${GPU_SLUG}/v1/chat/completions"
EXT="${MAAS_URL}/llm/${EXT_SLUG}/v1/chat/completions"

log "=== Daily observability traffic ==="
log "MAAS_URL=${MAAS_URL}"
log "sim=${SIM_SLUG} gpu=${GPU_SLUG} ext=${EXT_SLUG}"

if $QUICK; then
  LOOPS=1
  GPU_TOK=25
else
  LOOPS=3
  GPU_TOK=50
fi

log "--- Retail analyst (${DEMO_RETAIL_SUB}) — low volume ---"
for i in $(seq 1 "$LOOPS"); do
  run_chat "retail-sim-${i}" "$SIM" "$DEMO_RETAIL_KEY" "$SIM_MODEL" \
    "\"Retail compliance checklist item ${i} for branch audit.\"" 35
  run_chat "retail-ext-${i}" "$EXT" "$DEMO_RETAIL_KEY" "$EXT_MODEL" \
    "\"Summarize KYC requirements (${i}).\"" 30
done

log "--- Risk analytics (${DEMO_RISK_SUB}) — high GPU volume ---"
for i in $(seq 1 "$LOOPS"); do
  run_chat "risk-gpu-${i}" "$GPU" "$DEMO_RISK_KEY" "$GPU_MODEL" \
    "\"Analyze credit risk exposure and capital adequacy for portfolio scenario ${i}. Include PD, LGD, and EAD factors.\"" \
    "$GPU_TOK"
  run_chat "risk-ext-${i}" "$EXT" "$DEMO_RISK_KEY" "$EXT_MODEL" \
    "\"Draft risk committee memo section ${i}.\"" 40
done

log "--- Platform ops (${DEMO_PLATFORM_SUB}) — cross-model ---"
for i in $(seq 1 "$LOOPS"); do
  run_chat "platform-sim-${i}" "$SIM" "$DEMO_PLATFORM_KEY" "$SIM_MODEL" \
    "\"Platform health check ${i}.\"" 20
  run_chat "platform-gpu-${i}" "$GPU" "$DEMO_PLATFORM_KEY" "$GPU_MODEL" \
    "\"Gateway routing validation ${i}.\"" 30
  run_chat "platform-ext-${i}" "$EXT" "$DEMO_PLATFORM_KEY" "$EXT_MODEL" \
    "\"External model smoke test ${i}.\"" 25
done

log "Done — check RHOAI Console → Observe & monitor → Observability"
