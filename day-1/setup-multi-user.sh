#!/usr/bin/env bash
# Day 1 optional — htpasswd IdP + demo persona groups for multi-user MaaS observability.
# Adds htpasswd alongside existing rhbk OpenID; does not remove other identity providers.
set -uo pipefail

DAY1_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS_ENV="$DAY1_DIR/demo-users-passwords.env"
HTPASSWD_SECRET="htpasswd-maas-demo-users"
HTPASSWD_IDP="maas-demo-users"
LOG="$DAY1_DIR/multi-user-setup.log"

exec > >(tee "$LOG") 2>&1

echo "=== Multi-user htpasswd setup: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

if [ ! -f "$PASS_ENV" ]; then
  echo "Missing $PASS_ENV — copy from demo-users-passwords.env.example"
  exit 1
fi

# shellcheck disable=SC1090
source "$PASS_ENV"

for var in HT_USER_RETAIL HT_USER_RISK HT_USER_PLATFORM HT_PASS_RETAIL HT_PASS_RISK HT_PASS_PLATFORM; do
  if [ -z "${!var:-}" ]; then
    echo "Required variable $var is not set in $PASS_ENV"
    exit 1
  fi
done

if ! command -v htpasswd >/dev/null 2>&1; then
  echo "htpasswd not found — install httpd-tools (brew install httpd) or use podman:"
  echo "  podman run --rm -v /tmp:/tmp docker.io/httpd:2.4 htpasswd ..."
  exit 1
fi

HTFILE=$(mktemp)
trap 'rm -f "$HTFILE"' EXIT

htpasswd -Bbc "$HTFILE" "$HT_USER_RETAIL" "$HT_PASS_RETAIL"
htpasswd -Bb  "$HTFILE" "$HT_USER_RISK"    "$HT_PASS_RISK"
htpasswd -Bb  "$HTFILE" "$HT_USER_PLATFORM" "$HT_PASS_PLATFORM"

echo ""
echo "=== Step 1: htpasswd secret in openshift-config ==="
oc create secret generic "$HTPASSWD_SECRET" \
  --from-file=htpasswd="$HTFILE" \
  -n openshift-config --dry-run=client -o yaml | oc apply -f -

echo ""
echo "=== Step 2: Add htpasswd identity provider (merge with existing) ==="
if oc get oauth cluster -o jsonpath="{.spec.identityProviders[*].name}" | grep -qw "$HTPASSWD_IDP"; then
  echo "Identity provider $HTPASSWD_IDP already present — skipping OAuth patch"
else
  python3 <<PY
import json, subprocess, sys

name = "$HTPASSWD_IDP"
secret = "$HTPASSWD_SECRET"
raw = subprocess.check_output(["oc", "get", "oauth", "cluster", "-o", "json"])
oauth = json.loads(raw)
providers = oauth.setdefault("spec", {}).setdefault("identityProviders", [])
if any(p.get("name") == name for p in providers):
    print(f"Provider {name} already in OAuth spec")
    sys.exit(0)
providers.append({
    "name": name,
    "mappingMethod": "claim",
    "type": "HTPasswd",
    "htpasswd": {"fileData": {"name": secret}},
})
patch = json.dumps([{"op": "replace", "path": "/spec/identityProviders", "value": providers}])
subprocess.check_call(["oc", "patch", "oauth", "cluster", "--type=json", "-p", patch])
print(f"Added identity provider {name}")
PY
fi

echo ""
echo "=== Step 4: Demo persona groups ==="
oc apply -f "$DAY1_DIR/manifests/demo-groups.yaml"

echo ""
echo "=== Step 5: Verify groups ==="
oc get group maas-demo-retail-analyst maas-demo-risk-analytics maas-demo-platform-ops \
  -o custom-columns=NAME:.metadata.name,USERS:.users

echo ""
echo "=== Step 6: Smoke login (retail user) ==="
SERVER=$(oc whoami --show-server)
if oc login -u "$HT_USER_RETAIL" -p "$HT_PASS_RETAIL" --server="$SERVER" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
  echo "Login OK: $(oc whoami)"
  oc logout >/dev/null 2>&1 || true
else
  echo "[WARN] htpasswd login failed — OAuth may still be rolling out (wait ~30s and retry)"
fi

echo ""
echo "=== Multi-user setup complete ==="
echo "Next: apply day-6 persona subscriptions, then ./day-6/mint-persona-keys.sh"
