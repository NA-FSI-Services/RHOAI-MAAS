#!/usr/bin/env bash
# Day 1 installation — operators + platform config only (phases 1-2 per rhoai-maas-guide)
set -uo pipefail

GUIDE_DIR="$(cd "$(dirname "$0")/../work/rhoai-maas-guide" && pwd)"
OUT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$OUT_DIR/day1-install.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

exec > >(tee -a "$LOG") 2>&1

echo "=== Day 1 Installation Started: $TIMESTAMP ==="
echo "Guide: $GUIDE_DIR"
echo "User: $(oc whoami) @ $(oc whoami --show-server)"

run() {
  echo ""
  echo ">>> $*"
  "$@" || echo "[WARN] exit code $? from: $*"
}

# --- Phase 1: GPU scaling ---
echo ""
echo "=== Phase 1a: GPU MachineSet scaling (target: 3 GPUs) ==="
run oc get machineset -n openshift-machine-api | grep gpu
for ms in ocp-fklhz-worker-gpu-big-us-east-2b ocp-fklhz-worker-gpu-big-us-east-2c; do
  REPLICAS=$(oc get machineset "$ms" -n openshift-machine-api -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
  if [ "$REPLICAS" = "0" ]; then
    echo "Scaling $ms to 1 replica..."
    run oc patch machineset "$ms" -n openshift-machine-api --type=merge -p '{"spec":{"replicas":1}}'
  else
    echo "$ms already at replicas=$REPLICAS"
  fi
done

echo "Waiting up to 20 minutes for GPU nodes..."
GPU_TARGET=3
for i in $(seq 1 40); do
  GPU_COUNT=$(oc get nodes -o json | jq '[.items[] | select(.status.allocatable["nvidia.com/gpu"] != null) | .status.allocatable["nvidia.com/gpu"] | tonumber] | add // 0')
  echo "  [$i/40] Allocatable GPUs: $GPU_COUNT / $GPU_TARGET"
  [ "$GPU_COUNT" -ge "$GPU_TARGET" ] && break
  sleep 30
done
run oc get nodes "-o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu" | tee "$OUT_DIR/01-gpu-nodes-after-scale.txt"

# --- Phase 1b: Operators (selective — skip rhods on GitOps clusters) ---
echo ""
echo "=== Phase 1b: Operator subscriptions (excluding rhoai-operator) ==="
for comp in cert-manager connectivity-link service-mesh leader-worker-set; do
  run oc apply -k "$GUIDE_DIR/manifests/01-prerequisites/operators/$comp/"
done

echo "Waiting for operator CSVs (up to 10 min each)..."
for ns_label in \
  "redhat-ods-operator operators.coreos.com/rhods-operator.redhat-ods-operator" \
  "openshift-operators operators.coreos.com/rhcl-operator.openshift-operators" \
  "cert-manager-operator operators.coreos.com/openshift-cert-manager-operator.cert-manager-operator" \
  "openshift-operators operators.coreos.com/servicemeshoperator3.openshift-operators" \
  "openshift-lws-operator operators.coreos.com/leader-worker-set.openshift-lws-operator"
do
  ns="${ns_label%% *}"
  label="${ns_label#* }"
  echo "  Waiting CSV in $ns ($label)..."
  oc wait csv -n "$ns" -l "$label=" \
    --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s 2>/dev/null || \
    echo "  [WARN] CSV in $ns not Succeeded within timeout"
done
run oc get csv -n openshift-operators | grep -iE 'rhcl|servicemesh|authorino|limitador|cert-manager|leader-worker' | tee "$OUT_DIR/02-csv-openshift-operators.txt"
run oc get csv -n redhat-ods-operator | grep rhods | tee "$OUT_DIR/02-csv-rhods.txt"

# --- Phase 2: Platform config ---
echo ""
echo "=== Phase 2: Platform configuration ==="

if ! oc get kuadrant kuadrant -n kuadrant-system &>/dev/null; then
  run oc apply -f "$GUIDE_DIR/manifests/02-platform-config/kuadrant/namespace.yaml"
  run oc apply -f "$GUIDE_DIR/manifests/02-platform-config/kuadrant/service-annotation.yaml"
  run oc apply -f "$GUIDE_DIR/manifests/02-platform-config/kuadrant/kuadrant.yaml"
  run oc wait --for=condition=Ready kuadrant/kuadrant -n kuadrant-system --timeout=300s
else
  echo "Kuadrant CR already exists"
  run oc wait --for=condition=Ready kuadrant/kuadrant -n kuadrant-system --timeout=120s
fi

UWM_CFG=$(oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}' 2>/dev/null || true)
if ! echo "$UWM_CFG" | grep -q enableUserWorkload; then
  run oc apply -k "$GUIDE_DIR/manifests/02-platform-config/uwm/"
else
  echo "UWM already enabled"
fi

if ! oc get gatewayclass openshift-default &>/dev/null; then
  run oc apply -f "$GUIDE_DIR/manifests/02-platform-config/gatewayclass.yaml"
  run oc wait gatewayclass openshift-default --for=jsonpath='{.status.conditions[?(@.type=="Accepted")].status}'=True --timeout=60s
else
  echo "GatewayClass openshift-default already exists"
fi

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
CERT_NAME=$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate.name}')
[ -z "$CERT_NAME" ] && CERT_NAME="router-certs-default"

if ! oc get gateway maas-default-gateway -n openshift-ingress &>/dev/null; then
  export CLUSTER_DOMAIN CERT_NAME
  run envsubst '${CLUSTER_DOMAIN} ${CERT_NAME}' < "$GUIDE_DIR/manifests/02-platform-config/gateway.yaml.tmpl" | oc apply -f -
fi
run oc wait gateway/maas-default-gateway -n openshift-ingress --for=condition=Programmed --timeout=120s

EXISTING_ANNOTATION=$(oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.metadata.annotations.security\.opendatahub\.io/authorino-tls-bootstrap}' 2>/dev/null || echo "")
if [ "$EXISTING_ANNOTATION" != "true" ]; then
  run oc annotate gateway maas-default-gateway -n openshift-ingress \
    security.opendatahub.io/authorino-tls-bootstrap="true" --overwrite
else
  echo "Authorino TLS bootstrap annotation already set"
fi

# --- Exit criteria capture ---
echo ""
echo "=== Day 1 Exit Criteria ==="
{
  echo "Captured: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo ""
  echo "=== GPU Nodes ==="
  oc get nodes "-o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu" | grep -v '<none>' || true
  echo ""
  echo "=== Kuadrant ==="
  oc get kuadrant -n kuadrant-system
  echo ""
  echo "=== Gateways ==="
  oc get gateway -A -o 'custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status'
  echo ""
  echo "=== MaaS dependency CSVs ==="
  oc get csv -n openshift-operators | grep -iE 'rhcl|servicemesh|authorino|limitador' || true
  oc get csv -n redhat-ods-operator | grep rhods || true
} | tee "$OUT_DIR/07-day1-summary.txt"

echo ""
echo "=== Optional: Multi-user htpasswd setup ==="
if [ -f "$OUT_DIR/demo-users-passwords.env" ]; then
  chmod +x "$OUT_DIR/setup-multi-user.sh"
  "$OUT_DIR/setup-multi-user.sh"
else
  echo "Skip — copy demo-users-passwords.env.example to demo-users-passwords.env to enable"
fi

echo ""
echo "=== Day 1 Installation Complete ==="
