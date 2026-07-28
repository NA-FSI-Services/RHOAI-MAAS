#!/usr/bin/env bash
# Fix a Gen AI Studio playground so it can reach MaaS models.
#
# RHOAI 3.5-ea auto-config often creates OGX playgrounds with:
#   - VLLM_API_TOKEN_*=fake
#   - base_url http://maas-default-gateway-...svc...//v1  (404; wrong path)
#   - missing/incorrect provider_model_id for vLLM --served-model-name
# And chat via the UI BFF returns HTTP 500 if TrustyAI CRDs are absent.
#
# Usage:
#   ./scripts/fix-genai-playground-maas.sh <namespace> [subscription]
#   ./scripts/fix-genai-playground-maas.sh llm lob-admin
#   MAAS_KEY=sk-oai-... ./scripts/fix-genai-playground-maas.sh my-project
#
# Prerequisites: oc logged in as a user who can mint keys for [subscription]
# (default lob-admin). Do NOT click "Update playground configuration" after
# running this — the UI regenerates the broken auto-config.
set -euo pipefail

NS="${1:-}"
SUB="${2:-lob-admin}"
OGX_NAME="${OGX_NAME:-lsd-genai-playground}"
CM_NAME="${CM_NAME:-llama-stack-config}"

if [ -z "$NS" ]; then
  echo "Usage: $0 <playground-namespace> [subscription]"
  echo "Example: $0 llm lob-admin"
  exit 1
fi

if ! command -v oc >/dev/null 2>&1; then
  echo "oc not found"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found"
  exit 1
fi

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="${MAAS_URL:-https://maas.${CLUSTER_DOMAIN}}"

echo "=== Fix Gen AI playground MaaS wiring ==="
echo "namespace=$NS subscription=$SUB MAAS_URL=$MAAS_URL"

# --- TrustyAI (Gen AI BFF hard-fails without these CRDs) ---
TRUSTY=$(oc get dsc default-dsc -o jsonpath='{.spec.components.trustyai.managementState}' 2>/dev/null || echo "")
if [ "$TRUSTY" != "Managed" ]; then
  echo "Enabling TrustyAI (required for playground chat BFF)..."
  oc patch dsc default-dsc --type=merge -p \
    '{"spec":{"components":{"trustyai":{"managementState":"Managed","mcpGuardrailsMode":false}}}}'
fi
for i in $(seq 1 36); do
  if oc get crd nemoguardrails.trustyai.opendatahub.io >/dev/null 2>&1; then
    echo "TrustyAI NemoGuardrails CRD present"
    break
  fi
  sleep 5
done

if ! oc get ogxserver "$OGX_NAME" -n "$NS" >/dev/null 2>&1; then
  echo "OGXServer/$OGX_NAME not found in $NS — open Gen AI studio → Try in playground first"
  exit 1
fi
if ! oc get cm "$CM_NAME" -n "$NS" >/dev/null 2>&1; then
  echo "ConfigMap/$CM_NAME not found in $NS"
  exit 1
fi

# --- API key ---
if [ -z "${MAAS_KEY:-}" ]; then
  if [ -f /tmp/admin-lob-key.txt ]; then
    MAAS_KEY=$(cat /tmp/admin-lob-key.txt)
    echo "Using key from /tmp/admin-lob-key.txt"
  else
    echo "Minting MaaS API key for subscription=$SUB as $(oc whoami)..."
    RESP=$(/usr/bin/curl -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
      -H "Authorization: Bearer $(oc whoami -t)" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"playground-${NS}-$(date +%s)\",\"expiresIn\":\"720h\",\"subscription\":\"${SUB}\"}")
    MAAS_KEY=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('key') or '')" "$RESP")
    if [ -z "$MAAS_KEY" ]; then
      echo "Failed to mint key: $RESP"
      echo "Hint: login as the subscription owner, or set MAAS_KEY=sk-oai-..."
      exit 1
    fi
    umask 077
    printf '%s\n' "$MAAS_KEY" >/tmp/admin-lob-key.txt
    echo "Minted key (saved /tmp/admin-lob-key.txt)"
  fi
fi

# --- Patch ConfigMap + OGXServer ---
export NS CM_NAME OGX_NAME MAAS_URL MAAS_KEY
python3 <<'PY'
import json, os, re, subprocess, sys
from pathlib import Path

ns = os.environ["NS"]
cm_name = os.environ["CM_NAME"]
ogx_name = os.environ["OGX_NAME"]
maas_url = os.environ["MAAS_URL"].rstrip("/")
key = os.environ["MAAS_KEY"]

def oc_json(*args):
    return json.loads(subprocess.check_output(["oc", *args]))

# Map HF / display names → MaaSModelRef name + endpoint
refs = {}
for item in oc_json("get", "maasmodelref", "-A", "-o", "json").get("items", []):
    name = item["metadata"]["name"]
    ep = (item.get("status") or {}).get("endpoint") or f"{maas_url}/llm/{name}"
    refs[name] = ep.rstrip("/")

# LLMInferenceService.spec.model.name (HF id) → MaaS name
hf_to_maas = {}
for item in oc_json("get", "llminferenceservice", "-A", "-o", "json").get("items", []):
    maas = item["metadata"]["name"]
    hf = ((item.get("spec") or {}).get("model") or {}).get("name")
    if hf:
        hf_to_maas[hf] = maas
    hf_to_maas[maas] = maas

def resolve_maas(model_id: str):
    if model_id in refs:
        return model_id
    if model_id in hf_to_maas and hf_to_maas[model_id] in refs:
        return hf_to_maas[model_id]
    # fuzzy: strip org prefix
    short = model_id.split("/")[-1].lower().replace("_", "-")
    for name in refs:
        if name.lower() == short or short in name.lower() or name.lower() in short:
            return name
    return None

cm = oc_json("get", "cm", cm_name, "-n", ns, "-o", "json")
cfg = cm["data"]["config.yaml"]

# Pair provider blocks with registered model entries
# Providers: provider_id + base_url under inference:
provider_ids = re.findall(
    r"- provider_id: ((?:vllm|maas-vllm)[^\n]+)\n(?:.*\n){0,12}?      base_url: ([^\n]+)",
    cfg,
)
# Registered llm models with provider_id
reg_models = re.findall(
    r"- provider_id: ((?:vllm|maas-vllm)[^\n]+)\n    model_id: ([^\n]+)(?:\n    provider_model_id: ([^\n]+))?",
    cfg,
)

print("Detected providers:")
for pid, url in provider_ids:
    print(f"  {pid}: {url}")
print("Detected registered models:")
for row in reg_models:
    print(f"  {row}")

# Fix each provider base_url using matching registered model
for pid, old_url in provider_ids:
    model_id = None
    for rpid, mid, _pmid in reg_models:
        if rpid == pid:
            model_id = mid.strip()
            break
    if not model_id:
        print(f"WARN: no registered model for {pid}; skipping URL rewrite")
        continue
    maas_name = resolve_maas(model_id)
    if not maas_name:
        print(f"WARN: cannot map model_id={model_id!r} to a MaaSModelRef")
        continue
    new_url = f"{refs[maas_name]}/v1"
    # replace only this provider's base_url occurrence
    pattern = rf"(- provider_id: {re.escape(pid)}\n(?:.*\n){{0,12}}?      base_url: )([^\n]+)"
    cfg2, n = re.subn(pattern, rf"\g<1>{new_url}", cfg, count=1)
    if n:
        cfg = cfg2
        print(f"Set {pid} base_url -> {new_url}")
    # ensure provider_model_id is the served MaaS name
    block_pat = rf"(- provider_id: {re.escape(pid)}\n    model_id: {re.escape(model_id)}\n)(?:    provider_model_id: [^\n]+\n)?"
    cfg = re.sub(block_pat, rf"\1    provider_model_id: {maas_name}\n", cfg, count=1)

cm["data"]["config.yaml"] = cfg
Path("/tmp/fix-playground-cm.json").write_text(json.dumps(cm))
subprocess.check_call(["oc", "replace", "-f", "/tmp/fix-playground-cm.json"])
print("ConfigMap updated")

# OGXServer tokens for all VLLM_API_TOKEN_* slots present + common 1..3
ogx = oc_json("get", "ogxserver", ogx_name, "-n", ns, "-o", "json")
env = ogx["spec"]["workload"]["overrides"].setdefault("env", [])
by = {e["name"]: e for e in env}
token_names = {e["name"] for e in env if e["name"].startswith("VLLM_API_TOKEN_")}
token_names.update({f"VLLM_API_TOKEN_{i}" for i in range(1, max(4, len(provider_ids) + 1))})
for name in sorted(token_names):
    if name in by:
        by[name]["value"] = key
    else:
        env.append({"name": name, "value": key})
if "VLLM_TLS_VERIFY" in by:
    by["VLLM_TLS_VERIFY"]["value"] = "false"
else:
    env.append({"name": "VLLM_TLS_VERIFY", "value": "false"})

Path("/tmp/fix-playground-ogx.json").write_text(json.dumps(ogx))
# replace may warn about deprecated distribution name
subprocess.check_call(["oc", "replace", "-f", "/tmp/fix-playground-ogx.json"])
print(f"OGXServer tokens set for: {', '.join(sorted(token_names))}")
PY

echo "Restarting playground deployment..."
oc rollout restart "deploy/${OGX_NAME}" -n "$NS" 2>/dev/null \
  || oc delete pod -n "$NS" -l "ogx.io/server=${OGX_NAME}" --ignore-not-found
oc rollout status "deploy/${OGX_NAME}" -n "$NS" --timeout=180s 2>/dev/null || sleep 15

echo ""
echo "=== Verify ==="
oc exec -n "$NS" "deploy/${OGX_NAME}" -- \
  curl -sS -m 20 "http://127.0.0.1:8321/v1/models" 2>/dev/null \
  | python3 -c 'import json,sys
try:
  for m in json.load(sys.stdin).get("data",[]):
    mid=m.get("id","")
    if "sentence" in mid or "embed" in mid: continue
    print("-", mid)
except Exception as e:
  print("models probe failed:", e)' || echo "(models probe failed)"

echo ""
echo "Done. Hard-refresh the playground UI."
echo "Do NOT click 'Update playground configuration' (it regenerates broken defaults)."
echo "If chat still returns 500, confirm: oc get crd nemoguardrails.trustyai.opendatahub.io"
