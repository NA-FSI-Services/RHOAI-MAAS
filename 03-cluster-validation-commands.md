# Cluster Validation Commands

Copy-paste reference for inspecting cluster readiness before and during MaaS PoC setup.

**Prerequisites:** Logged in with `oc login` and `cluster-admin` (or sufficient read access).

```bash

export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
echo "Cluster domain: ${CLUSTER_DOMAIN}"
echo "MaaS gateway:   https://maas.${CLUSTER_DOMAIN}"
```

---

## 1. Baseline Cluster and GPU Topology

```bash
# OpenShift version (4.20+ recommended for RHOAI 3.4)
oc get clusterversion

# All nodes with roles and IPs
oc get nodes -o wide

# GPU allocation and instance types
oc get nodes -o=custom-columns=\
NAME:.metadata.name,\
GPU_ROLES:.metadata.labels.node-role\\.kubernetes\\.io/worker-gpu,\
GPU:.status.allocatable.nvidia\\.com/gpu,\
INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type

# Simple GPU count per node
oc get nodes "-o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu"

# GPU node detail (replace with your GPU worker hostname)
oc describe node ip-10-0-20-178.us-east-2.compute.internal | \
  grep -E 'instance-type|nvidia|Capacity|Allocatable|Roles'
```

**Expected (target state):** 3 worker nodes each showing `1` GPU.

---

## 2. Operator and RHOAI Component Health

```bash
# RHOAI operator
oc get csv -n redhat-ods-operator

# Platform operators (MaaS dependencies)
oc get csv -n openshift-operators | \
  grep -iE 'rhods|rhcl|servicemesh|authorino|limitador|serverless|knative'

# GPU stack
oc get csv -n openshift-nfd
oc get csv -n nvidia-gpu-operator | grep -i gpu

# DSC and initialization
oc get dsc,dsci
oc get datasciencecluster default-dsc -o yaml

# All DSC conditions (look for ModelsAsServiceReady)
oc get datasciencecluster default-dsc -o jsonpath='{range .status.conditions[*]}{.type}{"\t"}{.status}{"\t"}{.message}{"\n"}{end}'

# KServe / MaaS component state specifically
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.kserve}{"\n"}'
oc get datasciencecluster default-dsc -o jsonpath='{range .status.conditions[?(@.type=="ModelsAsServiceReady")]}{.status}{" "}{.message}{"\n"}{end}'
```

**Expected (target state):** All relevant CSVs `Succeeded`; `ModelsAsServiceReady` = `True`.

---

## 3. MaaS Platform Stack

```bash
# Kuadrant control plane
oc get kuadrant -n kuadrant-system
oc get pods -n kuadrant-system

# Gateways
oc get gateway -A
oc get gateway maas-default-gateway -n openshift-ingress -o yaml

# Auth and rate-limit policies
oc get authpolicy,ratelimitpolicy,tokenratelimitpolicy -A

# MaaS API
oc get deploy,pod,svc,route -n maas-api
oc logs deploy/maas-api -n maas-api --tail=30

# Database secret (required for API keys)
oc get secret -A | grep -i maas-db
oc get secret maas-db-config -n redhat-ods-applications 2>/dev/null || \
  echo "maas-db-config not found"

# MaaS CRD resources
oc api-resources --api-group=maas.opendatahub.io
oc get maasmodelref,maassubscription,tenant,externalmodel -A

# GatewayConfig (RHOAI built-in gateway)
oc get gatewayconfig -A
```

**Expected (target state):** `maas-default-gateway` Programmed; `maas-db-config` exists; MaaS CRs present.

---

## 4. Model Serving State

```bash
# All inference services
oc get llminferenceservice,inferenceservice -A

# KServe pods with node placement
oc get pods -A -l app.opendatahub.io/kserve=true -o wide

# Qwen-specific (current deployment)
oc get llminferenceservice qwen3-4b-instruct -n llm -o yaml
oc get pods -n llm -o wide

# Granite / simulator (deployed in llm namespace)
oc get llminferenceservice granite-4-tiny-gpu,facebook-opt-125m-simulated -n llm
oc get pods -n llm -o wide

# MaaS CRs
oc get maasmodelref -n llm
oc get maassubscription,tenant -n models-as-a-service

# Hardware profiles
oc get hardwareprofile -A

# HTTP routes
oc get httproute -A
oc get route -A | grep -i maas
```

---

## 5. Gateway Smoke Tests

```bash
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
export MAAS_URL="https://maas.${CLUSTER_DOMAIN}"

# Unauthenticated — expect 401 when ready (503 if routing incomplete)
curl -sk -o /dev/null -w "HTTP %{http_code}\n" "${MAAS_URL}/v1/models"

curl -sk -o /dev/null -w "HTTP %{http_code}\n" \
  -X POST "${MAAS_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"facebook-opt-125m-simulated","messages":[{"role":"user","content":"Ping"}]}'

# MaaS API health (operator-managed)
curl -sk -o /dev/null -w "health: HTTP %{http_code}\n" "${MAAS_URL}/maas-api/health"

# Direct model paths
curl -sk -o /dev/null -w "granite: HTTP %{http_code}\n" \
  "${MAAS_URL}/llm/granite-4-tiny-gpu/v1/models"
curl -sk -o /dev/null -w "simulator: HTTP %{http_code}\n" \
  "${MAAS_URL}/llm/facebook-opt-125m-simulated/v1/models"

# Qwen (pre-existing)
curl -sk -o /dev/null -w "HTTP %{http_code}\n" \
  "${MAAS_URL}/llm/qwen3-4b-instruct/v1/models"
```

**Expected (ready state):**

| Request | Expected HTTP | Status (Day 3) |
|---------|---------------|----------------|
| No bearer token | 401 | **401** |
| `/maas-api/health` | 200 | **200** |
| Valid basic key + simulator (model path) | 200 | **200** |
| Basic key + granite | 403 | **403** |
| Token limit exceeded | 429 | **429** |

---

## 6. NeMo Guardrails and Observability (Day 3)

```bash
# Guardrails CR
oc get nemoguardrails -A
oc get pods -n redhat-ods-applications | grep -i nemo

# Observability dashboard flag
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o yaml | \
  grep -A5 observability

# Observability operators
oc get csv -A | grep -iE 'grafana|observability|otel|cluster-observability'
```

---

## 7. Quick Health Check Script

Save and run for a one-page status summary:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Cluster Version ==="
oc get clusterversion -o custom-columns=VERSION:.status.desired.version,AVAILABLE:.status.conditions[0].status

echo -e "\n=== GPU Nodes ==="
oc get nodes "-o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu" | grep -v '<none>' || true

echo -e "\n=== RHOAI / MaaS Operators ==="
oc get csv -n redhat-ods-operator -o custom-columns=NAME:.metadata.name,PHASE:.status.phase | grep rhods

echo -e "\n=== DSC MaaS Condition ==="
oc get datasciencecluster default-dsc -o jsonpath='ModelsAsServiceReady: {range .status.conditions[?(@.type=="ModelsAsServiceReady")]}{.status}{" ("}{.message}{")"}{end}{"\n"}'

echo -e "\n=== Gateways ==="
oc get gateway -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status

echo -e "\n=== MaaS API ==="
oc get deploy maas-api -n redhat-ods-applications -o custom-columns=READY:.status.readyReplicas,DESIRED:.spec.replicas 2>/dev/null || echo "operator maas-api not found"
oc get deploy maas-api -n maas-api -o custom-columns=READY:.status.readyReplicas,DESIRED:.spec.replicas 2>/dev/null || echo "legacy maas-api not found"

echo -e "\n=== MaaS CRs ==="
oc get maasmodelref,maassubscription -A 2>/dev/null || echo "No MaaS CRs"

echo -e "\n=== Models ==="
oc get llminferenceservice -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status
```

---

## Related Documents

- [02-cluster-current-state.md](02-cluster-current-state.md) — assessed snapshot
- [04-installation-and-ready-state.md](04-installation-and-ready-state.md) — remediation steps
- [06-troubleshooting.md](06-troubleshooting.md) — known issues
