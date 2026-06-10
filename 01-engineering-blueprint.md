# Engineering Blueprint: Centralized Model-as-a-Service Governance in Red Hat OpenShift AI 3.4

> **Source:** Comprehensive Engineering Report and Technical Sales Demonstration Blueprint (converted from docx)  
> **Context:** Enterprise MaaS PoC — AI gateway as a "single front door"  
> **Cluster callout:** Example layout uses **3× g6e.2xlarge** GPU nodes (Day 1). Guide recommends `granite-tiny-gpu` for modest GPUs—not the docx `granite-3-8b-instruct` multi-replica layout.

### Guide models (rhoai-maas-guide)

| Model key | GPU | Notes |
|-----------|-----|-------|
| `simulator` | No | CPU-only demo |
| `granite-tiny-gpu` | Yes (~8 GB) | **Use on this cluster** (g6e/L4 class) |
| `gpt-oss-20b` | Yes (>= 40 GB) | Large GPU only |

---

## Executive Summary

Scaling generative AI in regulated enterprises requires platform-level governance beyond basic model serving. Financial services and other regulated industries need centralized security, resource boundaries, auditability, and cost attribution before deploying LLMs in production.

Red Hat OpenShift AI (RHOAI) 3.4 introduces the built-in **Models-as-a-Service (MaaS)** platform, powered by **Red Hat Connectivity Link (RHCL)**. MaaS provides:

- Declarative, subscription-based governance
- Self-service credential lifecycle management
- Token-based rate limiting
- Content safety filtering

This document covers the technical blueprint, feature support matrix, demonstration asset catalog, installation guide, and 3-day execution plan.

---

## Industry Use Cases

| Pattern | Focus |
|---------|-------|
| **Per-LOB isolation** | Per-use-case isolation, token masking, credential rotation, token-based rate limiting for burst analytics workloads |
| **Enterprise gateway** | Organization-wide "single front door" for compliance, deep auditing, and model routing |
| **Workbench modernization** | AI Workbench replacement; Triton/vLLM runtimes, GPU time-slicing, Elyra pipelines, canary rollouts |
| **Hybrid routing** | Multi-cluster (cloud + on-prem) unified routing to self-hosted and external OpenAI-compatible endpoints |

---

## Platform Compatibility

RHOAI 3.4 requires OpenShift Container Platform **4.19.9+, 4.20, or 4.21** on **x86_64**. Production deployments typically target **OCP 4.20+**.

### Feature Support Lifecycle Matrix

| Component / Feature | Midstream Version | Lifecycle | Notes |
|---------------------|-------------------|-----------|-------|
| MaaS Gateway (Kuadrant/RHCL) | MaaS v0.1.1 / RHCL 1.3+ | **GA** | Deployed via DataScienceCluster CR |
| Subscription Quotas (MaaSSubscription) | MaaS API v0.1.1 | **GA** | Token limits, requests, priority tiers |
| Self-Service API Keys | MaaS API v0.1.1 | **GA** | Minting, expiration, rotation, revocation |
| OIDC Direct Authentication | RHCL GatewayConfig | **GA** | Keycloak, Azure AD federation |
| NeMo Guardrails Integration | TrustyAI Operator v1.37.0 | **GA** | Regex rails, OTel metrics |
| Distributed Inference (llm-d) | llm-d v0.7.1 | **GA** | Multi-model scheduling, prefill/decode disaggregation |
| MaaS Observability Dashboard | Perses / Grafana | **TP** | **Implemented Day 6** — COO + per-user personas |
| External Model Egress | MaaS API v0.1.1 | **TP** | **Implemented Day 5** — LiteLLM workshop via `ExternalModel` |
| Raw vLLM Serving | KServe v0.17.0 | **TP** | Direct vLLM without EPP constraints |
| Workload Variant Autoscaler | KEDA-based | **TP** | Dynamic replica scaling |
| Priority-Based Flow Control | EPP Scheduler v0.7.1 | **TP** | Batch + real-time co-location |
| MCP Gateway & Lifecycle | MCP Operator | **TP / DP** | Identity-aware tool routing |
| Cost Management & Showback | MaaS telemetry | **DP** | Dollar-denominated cost tracking |
| Cross-Datacenter Rate Limiting | Coordinated Limitador | **Roadmap 3.6** | Global quota sync |
| Semantic Response Caching | vLLM Semantic Router | **Roadmap** | Exact/semantic response caching |

---

## Hardware Specification and Cluster Topology

Demonstration layout optimized for **3x AWS g6.4xlarge** workers:

| Parameter | Single Node | 3-Node Total |
|-----------|-------------|--------------|
| vCPUs | 16 (AMD EPYC 7R13) | 48 |
| System Memory | 64 GiB | 192 GiB |
| Physical Accelerators | 1x NVIDIA L4 | 3x NVIDIA L4 |
| GPU Architecture | Ada Lovelace (AD104) | Unified Ada Lovelace |
| VRAM per GPU | 24 GB GDDR6 ECC | 72 GB cumulative |
| Network | Up to 25 Gbps | Dedicated VPC fabric |
| Local Storage | 600 GB NVMe | 1.8 TB total |

> **Cluster callout:** Example sandbox may start with **1× g6e.2xlarge** (1 GPU). Scale to 3 GPU workers before full Granite + Guardrails layout.

### GPU Workload Allocation Strategy

| Node | Workload |
|------|----------|
| GPU Node 1 | Primary `granite-3-8b-instruct` (FP8 ~8.5 GB weights) |
| GPU Node 2 | Secondary Granite replica (EPP cache-locality routing) |
| GPU Node 3 | NeMo Guardrails orchestrator + classification |
| CPU workers | CPU-based simulator model (multi-model routing demo) |

---

## Demonstration Asset Index

### RHDP Catalog Assets (demo.redhat.com)

| Asset | Purpose |
|-------|---------|
| APD / OpenShift Container Platform | Multi-node OCP with ODF storage; 3x g6.4xlarge workers |
| TAP with Developer Hub | RHDH with AI software templates |
| Field Content CI | Custom GitOps/Helm configurations |

### Code Repositories

| Repository | URL |
|------------|-----|
| RHOAI MaaS Guide | https://github.com/rh-aiservices-bu/rhoai-maas-guide |
| Upstream MaaS | https://github.com/opendatahub-io/models-as-a-service |

### Media and Reference

| Resource | URL |
|----------|-----|
| Official MaaS Feature Video | https://drive.google.com/file/d/17pLFqDMEi2-XjxsWp70saDPyb_IHHoHf/view |
| AI Gateway Flow Animation | https://noyitz.github.io/ai-gateway-docs/ai-gateway-flow.html |
| Model Signing Demo (RHTAS) | https://drive.google.com/file/d/1eZq40RzaphljAHk4LcIWGZOs654xLcvQ/view |

---

## Core Architecture

RHOAI 3.4 MaaS acts as **Policy Enforcement Point (PEP)** and **Policy Decision Point (PDP)** between consumer applications and model serving engines.

```
[Consumer Application]
        |  POST /v1/chat/completions (API Key)
        v
  <-- gRPC CheckRequest --> [Authorino Auth Engine]
        |                          |
        |  Stripped Key / Injected Secrets
        v
   [Node 1: vLLM]    [Node 2: vLLM]
```

### Zero-Trust Parameters

1. **Body-Based Routing (BBR):** WASM plugin in Envoy inspects JSON payload `"model"` field and promotes it to an internal header for Istio routing.
2. **EPP Load Distribution:** Endpoint Picker monitors KV cache utilization, prefix cache matches, and queue scoring across GPU nodes.
3. **Credential Exfiltration Mitigation:** Authorino verifies bearer key, strips client `Authorization` header, injects model-specific credentials from Kubernetes Secrets before forwarding to inference engines.

---

## Installation Guide (rhoai-maas-guide)

### Prerequisites

- OCP 4.19.9+, 4.20, or 4.21
- `cluster-admin` access
- CLI tools: `oc`, `kustomize` (v5.x), `envsubst`, `jq`, `curl`

### Step 1: Platform Operators and Service Mesh

```bash
git clone https://github.com/rh-aiservices-bu/rhoai-maas-guide.git
cd rhoai-maas-guide
oc apply -k 01-prerequisites/operators/
oc get csv -n openshift-operators
```

Apply Kuadrant, UWM, GatewayClass:

```bash
oc apply -k 02-platform-config/kuadrant/
oc wait --for=condition=Ready kuadrant/kuadrant -n kuadrant-system --timeout=120s
oc apply -k 02-platform-config/uwm/
oc apply -f 02-platform-config/gatewayclass.yaml
```

Deploy gateway:

```bash
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
export CERT_NAME=$(oc get ingresscontroller/default -n openshift-ingress-operator -o jsonpath='{.spec.routeAdmission.wildcardPolicy}')
INGRESS_MODE=clusterip ./scripts/setup-gateway.sh
oc wait --for=condition=Programmed gateway/maas-default-gateway -n openshift-ingress --timeout=120s
```

### Step 2: RHOAI Operator and DSC

```yaml
# 03-rhoai-config/datasciencecluster.yaml
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    kserve:
      managementState: Managed
      rawDeploymentServiceConfig: Headed
      modelsAsService:
        managementState: Managed
    dashboard:
      managementState: Managed
    llamastackoperator:
      managementState: Managed
```

```bash
oc apply -k 03-rhoai-config/
oc wait --for=jsonpath='{.status.components.kserve.modelsAsService.state}'=Managed datasciencecluster/default-dsc --timeout=300s
oc rollout status deployment/maas-api -n redhat-ods-applications --timeout=120s
```

> **Cluster callout:** Current DSC has `modelsAsService` **Removed**. Must patch before governance demos.

### Step 3: PostgreSQL Database

```bash
./scripts/setup-maas.sh --from-phase 4
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: maas-db-config
  namespace: redhat-ods-applications
type: Opaque
stringData:
  DB_CONNECTION_URL: "postgresql://maas_user:maas_password@maas-db.redhat-ods-applications.svc.cluster.local:5432/maas?sslmode=disable"
```

```bash
oc rollout restart deployment/maas-api -n redhat-ods-applications
oc rollout status deployment/maas-api -n redhat-ods-applications --timeout=120s
```

### Step 4: Models and MaaSModelRef

**Hardware Profile (L4 GPU):**

```yaml
apiVersion: infrastructure.opendatahub.io/v1
kind: HardwareProfile
metadata:
  name: nvidia-l4-gpu
  namespace: redhat-ods-applications
spec:
  identifiers:
    - identifier: cpu
      displayName: CPU
      defaultCount: '4'
      minCount: 2
      maxCount: '8'
      resourceType: CPU
    - identifier: memory
      displayName: Memory
      defaultCount: 16Gi
      minCount: 8Gi
      maxCount: 32Gi
      resourceType: Memory
    - identifier: nvidia.com/gpu
      displayName: NVIDIA L4 GPU
      defaultCount: 1
      minCount: 1
      maxCount: 1
      resourceType: Accelerator
```

**Granite LLMInferenceService (2 replicas):**

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: granite-3-8b-instruct
  namespace: models-as-a-service
  annotations:
    opendatahub.io/hardware-profile-name: nvidia-l4-gpu
    opendatahub.io/hardware-profile-namespace: redhat-ods-applications
    security.opendatahub.io/enable-auth: "false"
spec:
  replicas: 2
  model:
    uri: hf://ibm-granite/granite-3.0-8b-instruct
    name: granite-3-8b-instruct
  router:
    scheduler:
      template:
        containers:
          - name: main
            args:
              - --pool-group
              - inference.networking.x-k8s.io
              - --pool-name
              - granite-inference-pool
              - --pool-namespace
              - models-as-a-service
              - --config-text
              - |
                apiVersion: inference.networking.x-k8s.io/v1alpha1
                kind: EndpointPickerConfig
                plugins:
                  - type: queue-scorer
                  - type: kv-cache-utilization-scorer
                  - type: prefix-cache-scorer
                schedulingProfiles:
                  - name: default
                    plugins:
                      - pluginRef: queue-scorer
                        weight: 2
                      - pluginRef: kv-cache-utilization-scorer
                        weight: 2
                      - pluginRef: prefix-cache-scorer
                        weight: 3
  template:
    tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
    containers:
      - name: main
        image: vllm/vllm-openai:v0.8.4
        env:
          - name: VLLM_USE_V1
            value: "0"
          - name: HF_HOME
            value: "/tmp/hf_home"
          - name: VLLM_ADDITIONAL_ARGS
            value: "--dtype=half --max-model-len=4096 --gpu-memory-utilization=0.85 --enforce-eager"
        resources:
          limits:
            cpu: '8'
            memory: 32Gi
            nvidia.com/gpu: "1"
          requests:
            cpu: '4'
            memory: 16Gi
            nvidia.com/gpu: "1"
```

**MaaSModelRef:**

```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSModelRef
metadata:
  name: granite-3-8b-ref
  namespace: models-as-a-service
spec:
  modelName: granite-3-8b-instruct
  targetRef:
    kind: InferenceService
    name: granite-3-8b-instruct
    namespace: models-as-a-service
```

```bash
oc apply -f 05-maas-models/nvidia-l4-profile.yaml
oc apply -f 05-maas-models/granite-serving.yaml
./scripts/deploy-model.sh --model simulator
oc apply -f 05-maas-models/granite-ref.yaml
oc get pods -n models-as-a-service -o wide
```

---

## Feature Demonstration Reference

### Multi-Model Gateway Routing

Single client endpoint; `"model"` field in payload routes to local or external models via WASM plugin.

### Authentication, Authorization, and RBAC

**Subscriptions:**

```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: basic-team-subscription
  namespace: models-as-a-service
spec:
  displayName: "Basic Team Subscription"
  priority: 10
  groups:
    - basic-users-group
  quotas:
    - modelRef: local-simulator
      tokenLimit: 100000
      rateLimits:
        - limit: 20
          window: 1m
          metric: requests
---
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: advanced-analytics-subscription
  namespace: models-as-a-service
spec:
  displayName: "Advanced Analytics Subscription"
  priority: 20
  groups:
    - advanced-users-group
  quotas:
    - modelRef: granite-3-8b-ref
      tokenLimit: 5000000
      rateLimits:
        - limit: 100
          window: 1m
          metric: requests
```

**Verification scenarios:** 401 (no key), 200 (authorized), 403 (entitlement mismatch), 429 (token rate limit).

### Technical Options (Extended Demo)

- **External OIDC:** Tenant CR `externalOIDC` spec with Keycloak/Azure AD
- **NeMo Guardrails:** TrustyAI CR on dedicated GPU node
- **Observability showback:** `observabilityDashboard: true` on OdhDashboardConfig (TP)

---

## Presentation Deck Outline

| Slide | Title | Key Points |
|-------|-------|------------|
| 1 | Title & Executive Summary | Single front door; platform-level governance |
| 2 | GenAI Scaling Paradox | Cost, security, compliance risks of ungoverned AI |
| 3 | Architecture Blueprint | BBR, Authorino zero-trust token masking |
| 4 | Live Demo Scenarios | 401 / 403 / 429 deterministic proofs |
| 5 | Fleet Economics | EPP scheduling, multi-replica pooling |
| 6 | Observability & Next Steps | Token showback, multi-cluster path forward |

---

## References

- [Govern LLM access with Models-as-a-Service (RHOAI 3.4)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/govern_llm_access_with_models-as-a-service/index)
- [Route external and local LLMs with MaaS](https://developers.redhat.com/articles/2026/05/25/route-external-and-local-llms-models-as-a-service)
- [RHOAI Supported Configurations 3.x](https://access.redhat.com/articles/rhoai-supported-configs-3.x)
- [RHOAI 3.4 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes/new-features-and-enhancements_relnotes)
- [NeMo Guardrails (RHOAI 3.4)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/enabling_ai_safety_with_guardrails/enabling-ai-safety-with-nemo-guardrails_nemo-guardrails)
