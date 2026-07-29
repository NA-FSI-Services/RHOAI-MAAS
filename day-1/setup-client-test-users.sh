#!/usr/bin/env bash
# Add client-test htpasswd users to the existing htpasswd_provider IdP,
# create LOB groups, and apply MaaS subscriptions / auth / RBAC.
set -uo pipefail

DAY1_DIR="$(cd "$(dirname "$0")" && pwd)"
POC_DIR="$(cd "$DAY1_DIR/.." && pwd)"
LOG="$DAY1_DIR/client-test-users-setup.log"
HTPASSWD_SECRET="htpasswd-secret"
HTPASSWD_NS="openshift-config"

USERS=(Adam Brenda Charlotte Daniel Emma Francis)

exec > >(tee "$LOG") 2>&1

echo "=== Client-test users setup: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

if ! command -v htpasswd >/dev/null 2>&1; then
  echo "htpasswd not found — install httpd-tools (macOS: brew install httpd)"
  exit 1
fi

if ! command -v oc >/dev/null 2>&1; then
  echo "oc not found"
  exit 1
fi

TMPDIR_HT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_HT"' EXIT
HTFILE="$TMPDIR_HT/htpasswd"

echo ""
echo "=== Step 1: Merge users into existing htpasswd-secret (keep admin) ==="
oc extract secret/"$HTPASSWD_SECRET" -n "$HTPASSWD_NS" --to="$TMPDIR_HT/cur" --confirm
cp "$TMPDIR_HT/cur/htpasswd" "$HTFILE"

for u in "${USERS[@]}"; do
  pass="${u}-1234"
  if grep -q "^${u}:" "$HTFILE"; then
    htpasswd -Bb "$HTFILE" "$u" "$pass"
    echo "Updated password for $u"
  else
    htpasswd -Bb "$HTFILE" "$u" "$pass"
    echo "Added user $u"
  fi
done

oc create secret generic "$HTPASSWD_SECRET" \
  --from-file=htpasswd="$HTFILE" \
  -n "$HTPASSWD_NS" --dry-run=client -o yaml | oc apply -f -
# Force OAuth pods to reload the secret
oc delete pod -n openshift-authentication -l app=oauth-openshift --ignore-not-found
echo "htpasswd secret updated; waiting for oauth pods..."
sleep 15
oc rollout status deployment/oauth-openshift -n openshift-authentication --timeout=180s 2>/dev/null || true

echo ""
echo "=== Step 2: OpenShift groups ==="
oc apply -f "$DAY1_DIR/manifests/client-test-groups.yaml"

echo ""
echo "=== Step 3: Self-provisioner (RHOAI project creation) ==="
# Allow LOB groups to create their own namespaces/projects for Gen AI playground
for g in maas-lob-retail maas-lob-risk maas-lob-platform maas-lob-executive; do
  oc adm policy add-cluster-role-to-group self-provisioner "$g" 2>/dev/null || \
    oc create clusterrolebinding "self-provisioner-${g}" \
      --clusterrole=self-provisioner --group="$g" --dry-run=client -o yaml | oc apply -f -
done

echo ""
echo "=== Step 4: MaaS subscriptions, auth policies, RBAC, free-tier lockdown ==="
oc apply -f "$POC_DIR/day-6/manifests/client-test-subscriptions.yaml"
oc apply -f "$POC_DIR/day-6/manifests/client-test-auth-policies.yaml"
oc apply -f "$POC_DIR/day-6/manifests/admin-subscription.yaml"
oc apply -f "$POC_DIR/day-6/manifests/client-test-maas-api-rbac.yaml"
# RHOAI project dropdown only lists namespaces with this label
oc label namespace llm opendatahub.io/dashboard=true --overwrite 2>/dev/null || true
oc apply -f "$POC_DIR/day-6/manifests/client-test-llm-catalog-rbac.yaml"
oc apply -f "$POC_DIR/day-6/manifests/client-test-restrict-free-subscriptions.yaml"

echo ""
echo "=== Step 5: Verify groups and subscriptions ==="
oc get group maas-lob-retail maas-lob-risk maas-lob-platform maas-lob-executive \
  -o custom-columns=NAME:.metadata.name,USERS:.users
oc get maassubscription -n models-as-a-service \
  -l maas.opendatahub.io/client-test=true \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,PRIORITY:.spec.priority

echo ""
echo "=== Step 6: Smoke login (Adam) without replacing admin kubeconfig ==="
SERVER=$(oc whoami --show-server)
ADMIN_WHO=$(oc whoami 2>/dev/null || echo unknown)
SMOKE_KC="$TMPDIR_HT/smoke.kubeconfig"
# Start from empty kubeconfig so admin session is preserved
KUBECONFIG="$SMOKE_KC" oc login -u Adam -p 'Adam-1234' --server="$SERVER" --insecure-skip-tls-verify=true >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "Login OK: $(KUBECONFIG="$SMOKE_KC" oc whoami) groups=$(KUBECONFIG="$SMOKE_KC" oc whoami --show-groups 2>/dev/null | tr '\n' ' ')"
else
  echo "[WARN] Adam login failed — wait for OAuth rollout and retry: oc login -u Adam -p 'Adam-1234'"
fi
echo "Admin session unchanged: $ADMIN_WHO"

echo ""
echo "=== Client-test users setup complete ==="
echo "Share: CLIENT-TEST-ACCESS.md (credentials + test plan)"