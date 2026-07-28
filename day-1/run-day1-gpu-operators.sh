#!/usr/bin/env bash
# Install NFD + NVIDIA GPU Operator and apply NFD instance + ClusterPolicy.
# Used by the RHOAI 3.5-ea track on fresh sandboxes (see 08-rhoai-3.5-ea-install.md).
set -uo pipefail

echo "=== NFD + GPU Operator bootstrap: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

oc create ns openshift-nfd --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-nfd
  namespace: openshift-nfd
spec:
  targetNamespaces:
  - openshift-nfd
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  channel: stable
  installPlanApproval: Automatic
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc create ns nvidia-gpu-operator --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nvidia-gpu-operator-group
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
  - nvidia-gpu-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
EOF

echo "Waiting for NFD CSV..."
oc wait csv -n openshift-nfd -l operators.coreos.com/nfd.openshift-nfd= \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s || true

oc apply -f - <<'EOF'
apiVersion: nfd.openshift.io/v1
kind: NodeFeatureDiscovery
metadata:
  name: nfd-instance
  namespace: openshift-nfd
spec:
  operand:
    servicePort: 12000
  workerConfig:
    configData: |
      core:
        sleepInterval: 60s
EOF

echo "Waiting for GPU Operator CSV..."
oc wait csv -n nvidia-gpu-operator -l operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator= \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=900s || true

CSV=$(oc get csv -n nvidia-gpu-operator -o jsonpath='{.items[0].metadata.name}')
oc get csv "$CSV" -n nvidia-gpu-operator -o jsonpath='{.metadata.annotations.alm-examples}' \
  | python3 -c 'import json,sys
ex=json.loads(sys.stdin.read())
for e in ex:
  if e.get("kind")=="ClusterPolicy":
    print(json.dumps(e))' | oc apply -f -

echo "Waiting for allocatable GPUs (up to 20 min)..."
for i in $(seq 1 40); do
  GPU_COUNT=$(oc get nodes -o json | jq '[.items[] | select(.status.allocatable["nvidia.com/gpu"] != null) | .status.allocatable["nvidia.com/gpu"] | tonumber] | add // 0')
  echo "  [$i/40] Allocatable GPUs: $GPU_COUNT"
  [ "$GPU_COUNT" -ge 1 ] && break
  sleep 30
done
oc get nodes "-o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu"
oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}{"\n"}'
echo "=== GPU operator bootstrap complete ==="
