# Installation and Ready-State Runbook

3-day plan (+ Days 4–7 extensions) to bring a sandbox cluster from partial MaaS state to a production-grade Granite governance demonstration.

**Reference repository:** [rhoai-maas-guide](https://github.com/rh-aiservices-bu/rhoai-maas-guide)  
**Target cluster:** `https://api.<cluster-domain>:6443`  
**Gateway URL:** `https://maas.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')`

---

## Current Starting Point

See [02-cluster-current-state.md](02-cluster-current-state.md). Key facts (post Day 2):

- OCP 4.20.0, RHOAI 3.4.0 — baseline OK
- 3 GPU nodes (g6e.2xlarge); Granite, simulator, and Qwen running in `llm` namespace
- `modelsAsService` **Managed**; PostgreSQL and operator `maas-api` in `redhat-ods-applications`
- MaaSModelRefs and MaaSSubscriptions applied and Ready/Active
- **Blocker:** Gateway returns HTTP 500 on model inference paths (Day 3 fix required)

The existing Qwen deployment can remain. Granite and simulator deploy to **`llm`** namespace per the guide; subscriptions and auth policies live in **`models-as-a-service`**.

---

## Prerequisites

| Requirement | Command to verify |
|-------------|-------------------|
| cluster-admin | `oc auth can-i '*' '*' --all-namespaces` |
| OCP 4.20+ | `oc get clusterversion` |
| CLI tools | `oc`, `kustomize`, `envsubst`, `jq`, `curl`, `git` |
| Network egress | HuggingFace/OCI pull for Granite model weights |

```bash
git clone https://github.com/rh-aiservices-bu/rhoai-maas-guide.git
cd rhoai-maas-guide
oc login --token=<TOKEN> --server=https://api.<cluster-domain>:6443
```

> **Path note:** Guide manifests live under `manifests/` (e.g. `manifests/01-prerequisites/operators/`). Use `./scripts/setup-maas.sh` for automated phases or the Day 1 script at [day-1/run-day1-install.sh](day-1/run-day1-install.sh).

---

## Day 1: Infrastructure, GPU Scaling, and Operator Bootstrapping

**Goal:** 3 GPU workers, all platform operators reconciled, gateway programmed.

**Status (2026-06-05):** Completed — see [day-1/07-day1-summary.txt](day-1/07-day1-summary.txt) and [day-1/CHANGES.md](day-1/CHANGES.md).

### Phase 1 — Infrastructure (Morning)

#### 1.1 Scale GPU workers to 3

This cluster uses **MachineSets** (`worker-gpu-big`), not RHDP catalog reprovisioning. Scale zones 2b and 2c:

```bash
oc patch machineset ocp-fklhz-worker-gpu-big-us-east-2b -n openshift-machine-api \
  --type=merge -p '{"spec":{"replicas":1}}'
oc patch machineset ocp-fklhz-worker-gpu-big-us-east-2c -n openshift-machine-api \
  --type=merge -p '{"spec":{"replicas":1}}'
```

> **Instance type:** Nodes are **g6e.2xlarge** (not g6.4xlarge from the original blueprint). Each provides 1 GPU; sufficient for `granite-tiny-gpu` demo.

Verify after scaling (allow ~10 min for nodes to join):

```bash
oc get nodes "-o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu" | grep -v '<none>'
```

**Expected output (3 lines with GPU=1):**

```
ip-10-0-xx-xx.us-east-2.compute.internal   1
ip-10-0-xx-xx.us-east-2.compute.internal   1
ip-10-0-xx-xx.us-east-2.compute.internal   1
```

#### 1.2 Confirm GPU operator labels

```bash
oc describe node <gpu-node> | grep -E 'nvidia.com/gpu|instance-type'
```

### Phase 2 — Operator Installation (Afternoon)

Most operators were already installed. On **GitOps-managed clusters**, do **not** re-apply the full operator kustomize (it creates a duplicate RHOAI OperatorGroup). Apply selectively:

```bash
cd rhoai-maas-guide
# Safe on GitOps clusters — skips duplicate rhods OperatorGroup
oc apply -k manifests/01-prerequisites/operators/cert-manager/
oc apply -k manifests/01-prerequisites/operators/connectivity-link/
oc apply -k manifests/01-prerequisites/operators/service-mesh/
oc apply -k manifests/01-prerequisites/operators/leader-worker-set/

oc get csv -n openshift-operators | grep -iE 'rhcl|servicemesh|authorino|limitador'
oc get csv -n redhat-ods-operator | grep rhods
```

Or run the automated Day 1 script: [day-1/run-day1-install.sh](day-1/run-day1-install.sh) (includes remediation notes in [day-1/CHANGES.md](day-1/CHANGES.md)).

Apply platform configuration:

```bash
oc apply -k manifests/02-platform-config/kuadrant/   # skip if Kuadrant already Ready
oc wait --for=condition=Ready kuadrant/kuadrant -n kuadrant-system --timeout=300s

# REQUIRED: Authorino TLS serving cert (do not skip — gateway returns HTTP 500 without it)
oc apply -f manifests/02-platform-config/kuadrant/service-annotation.yaml
# Wait for secret (typically ~10s)
oc get secret authorino-server-cert -n kuadrant-system
oc patch authorino authorino -n kuadrant-system --type=merge --patch '{
  "spec": {"listener": {"tls": {"enabled": true, "certSecretRef": {"name": "authorino-server-cert"}}}}
}'
oc -n kuadrant-system set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt

oc apply -k manifests/02-platform-config/uwm/
oc apply -f manifests/02-platform-config/gatewayclass.yaml
```

Deploy or refresh MaaS gateway (if not already Programmed):

```bash
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
export CERT_NAME=$(oc get ingresscontroller/default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate.name}')
[ -z "$CERT_NAME" ] && CERT_NAME="router-certs-default"
envsubst '${CLUSTER_DOMAIN} ${CERT_NAME}' < manifests/02-platform-config/gateway.yaml.tmpl | oc apply -f -
oc annotate gateway maas-default-gateway -n openshift-ingress \
  security.opendatahub.io/authorino-tls-bootstrap="true" --overwrite
oc wait --for=condition=Programmed gateway/maas-default-gateway -n openshift-ingress --timeout=300s
```

### Day 1 Exit Criteria

- [x] 3 allocatable GPUs
- [x] Kuadrant Ready
- [x] `maas-default-gateway` Programmed
- [x] All MaaS dependency CSVs Succeeded

---

## Day 2: MaaS Activation, Database, and Model Deployment

**Goal:** Enable modelsAsService, PostgreSQL persistence, Granite + CPU simulator.

**Status (2026-06-05):** Completed (partial) — see [day-2/README.md](day-2/README.md) and [day-2/CHANGES.md](day-2/CHANGES.md).

> **Recommended approach:** Use the guide automation from Phase 3 onward, then deploy models explicitly if Qwen causes Phase 5 skip:
> ```bash
> cd rhoai-maas-guide
> ./scripts/setup-maas.sh --from-phase 3 --model granite-tiny-gpu --skip-verify
> ./scripts/deploy-model.sh --model granite-tiny-gpu
> ./scripts/deploy-model.sh --model simulator
> ```
> On GitOps clusters, prefer a **targeted DSC patch** for `modelsAsService` instead of full `03-rhoai-config/` apply (avoids enabling ray/feast/trainer).

### Model name reference (guide vs original blueprint)

| Guide key | LLMInferenceService name | `"model"` in JSON body | Namespace |
|-----------|--------------------------|------------------------|-----------|
| `granite-tiny-gpu` | `granite-4-tiny-gpu` | `granite-4-tiny-gpu` | `llm` |
| `simulator` | `facebook-opt-125m-simulated` | `facebook-opt-125m-simulated` | `llm` |

### Phase 1 — MaaS Control Plane (Morning)

#### 2.1 Enable modelsAsService in DSC

Patch the DataScienceCluster:

```bash
oc patch datasciencecluster default-dsc --type=merge -p '
{
  "spec": {
    "components": {
      "kserve": {
        "managementState": "Managed",
        "rawDeploymentServiceConfig": "Headed",
        "modelsAsService": {
          "managementState": "Managed"
        }
      }
    }
  }
}'
```

Or apply a targeted patch (preferred on GitOps clusters):

```bash
oc patch datasciencecluster default-dsc --type=merge -p '
{
  "spec": {
    "components": {
      "kserve": {
        "managementState": "Managed",
        "modelsAsService": { "managementState": "Managed" }
      }
    }
  }
}'
```

Or apply the full guide manifest (enables additional components — ray, feast, etc.):

```bash
oc apply -k manifests/03-rhoai-config/
```

Verify:

```bash
oc get datasciencecluster default-dsc -o jsonpath='{range .status.conditions[?(@.type=="ModelsAsServiceReady")]}{.status}{" "}{.message}{"\n"}{end}'
oc rollout status deployment/maas-api -n redhat-ods-applications --timeout=300s
oc get secret maas-db-config -n redhat-ods-applications
```

> **Note:** Operator-managed `maas-api` runs in `redhat-ods-applications` on port **8443**. A legacy GitOps deployment may still exist in `maas-api` namespace on port 8080 — scale it down before Day 3 demos (see [day-2/CHANGES.md](day-2/CHANGES.md)).

#### 2.2 Deploy PostgreSQL and database secret

```bash
./scripts/setup-maas.sh --from-phase 4
# Alternative:
# NAMESPACE=redhat-ods-applications ./scripts/setup-database.sh
```

Verify:

```bash
oc get secret maas-db-config -n redhat-ods-applications
oc get pods -n redhat-ods-applications | grep -i postgres
oc rollout status deployment/maas-api -n redhat-ods-applications --timeout=120s
```

### Phase 2 — Model Deployment (Afternoon)

#### 2.3 Create L4 HardwareProfile

```bash
oc apply -f 05-maas-models/nvidia-l4-profile.yaml
oc get hardwareprofile -n redhat-ods-applications
```

#### 2.4 Deploy Granite

Use guide model `granite-tiny-gpu` (single replica, OCI modelcar) instead of manual `granite-3-8b-instruct` YAML:

```bash
./scripts/deploy-model.sh --model granite-tiny-gpu
# Or full automation:
./scripts/setup-maas.sh --from-phase 5 --model granite-tiny-gpu
```

For multi-replica demo on 3 GPUs, patch replicas after deploy (optional):

```bash
oc patch llminferenceservice granite-4-tiny-gpu -n llm --type=merge -p '{"spec":{"replicas":2}}'
```

#### 2.5 Deploy CPU simulator

```bash
./scripts/deploy-model.sh --model simulator
oc get pods -n llm | grep facebook-opt
```

#### 2.6 Register MaaSModelRefs

Model refs are created automatically by `deploy-model.sh`. Verify:

```bash
oc get maasmodelref -n llm
oc get maassubscription -n models-as-a-service
```

#### 2.7 Remove legacy GitOps maas-api conflict (if present)

```bash
oc delete httproute maas-api-route -n maas-api 2>/dev/null || true
oc scale deployment maas-api -n maas-api --replicas=0
```

Verify gateway health:

```bash
export MAAS_URL="https://maas.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
curl -sk -o /dev/null -w "health: HTTP %{http_code}\n" "${MAAS_URL}/maas-api/health"
curl -sk -o /dev/null -w "models: HTTP %{http_code}\n" "${MAAS_URL}/v1/models"
```

### Day 2 Exit Criteria

- [x] `ModelsAsServiceReady=True`
- [x] `maas-db-config` secret present; operator `maas-api` healthy
- [x] Granite 1/1 replica Ready on GPU node (2 replicas optional)
- [x] CPU simulator Running on CPU worker
- [x] `MaaSModelRef` for granite and simulator Ready
- [x] `MaaSSubscription` CRs Active
- [ ] Gateway inference paths return 200/401 (not 500) — **Day 3 blocker**

---

## Day 3: Governance, Safety, and Rehearsal

**Goal:** Fix gateway inference, mint API keys, validate auth/rate-limit, enable observability.

**Status (2026-06-05):** Completed — see [day-3/README.md](day-3/README.md) and [day-3/CHANGES.md](day-3/CHANGES.md).

> **Day 3 blocker (resolved):** Missing `authorino-server-cert` caused gateway HTTP 500. Apply `service-annotation.yaml` and restart Authorino (see Day 1 platform config above).

### Phase 1 — Gateway fix and API keys (Morning)

#### 3.1 Authorino TLS (if gateway returns 500)

```bash
oc apply -f manifests/02-platform-config/kuadrant/service-annotation.yaml
oc rollout restart deployment/authorino -n kuadrant-system
oc get authorino authorino -n kuadrant-system -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

#### 3.2 Legacy maas-api cleanup (GitOps clusters)

```bash
oc scale deployment maas-api -n maas-api --replicas=0
oc delete httproute maas-api-route -n maas-api 2>/dev/null || true
```

#### 3.3 Mint API keys

On admin-only sandboxes, mint keys via MaaS API (no separate demo users required):

```bash
export MAAS_URL="https://maas.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
export ADMIN_TOKEN=$(oc whoami -t)

# Basic tier (simulator)
curl -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-basic","expiresIn":"48h","subscription":"simulator-free"}'

# Advanced tier (granite)
curl -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-advanced","expiresIn":"48h","subscription":"granite-tiny-gpu-premium"}'
```

Save returned `key` values as `BASIC_USER_KEY` and `ADVANCED_USER_KEY`.

#### 3.4 Validate auth flows

Use **model-specific paths** and correct model IDs (see [day-3/CHANGES.md](day-3/CHANGES.md)):

| Scenario | URL | Model ID | Expected |
|----------|-----|----------|----------|
| No auth | `.../llm/facebook-opt-125m-simulated/v1/chat/completions` | `facebook/opt-125m` | 401 |
| Basic + simulator | same | `facebook/opt-125m` | 200 |
| Basic + granite | `.../llm/granite-4-tiny-gpu/v1/chat/completions` | `granite-4-tiny-gpu` | 403 |
| Advanced + granite | same | `granite-4-tiny-gpu` | 200 |

Run scenarios from [05-demonstration-steps.md](05-demonstration-steps.md) Demo 2.

### Phase 2 — Verification and Observability (Afternoon)

#### 3.5 Enable observability dashboard (Technology Preview)

The UI flag alone is insufficient — Day 6 installs COO, RHOAI metrics storage, OpenTelemetry operator, and the Perses datasource secret. See [day-6/run-day6-install.sh](day-6/run-day6-install.sh) and [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md).

```bash
oc patch odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications --type=merge \
  -p '{"spec":{"dashboardConfig":{"observabilityDashboard":true}}}'
```

#### 3.6 End-to-end verification

```bash
cd rhoai-maas-guide
./scripts/verify-maas.sh --no-cleanup
```

Expected: **ALL CHECKS PASSED** (15/15).

#### 3.7 NeMo Guardrails (optional — completed Day 4)

Implemented in [day-4/](day-4/) — see [day-4/README.md](day-4/README.md). Uses CPU internal detectors (Presidio + regex) in `redhat-ods-applications`; no spare GPU required.

Run full demonstration script in [05-demonstration-steps.md](05-demonstration-steps.md).

### Day 3 Exit Criteria

- [x] Gateway returns 401 (not 500) on protected paths
- [x] API keys minted for basic and advanced tiers
- [x] Auth 401 / 200 / 403 verified
- [x] Rate limit 429 verified
- [x] `verify-maas.sh` full pass
- [x] Observability dashboard enabled
- [x] NeMo Guardrails — completed Day 4

---

## Day 4: Unified Routing, Guardrails, and Legacy Cleanup

**Goal:** Enable body-based `/v1/chat/completions`, deploy NeMo Guardrails, remove duplicate GitOps maas-api.

**Status (2026-06-05):** Completed — see [day-4/README.md](day-4/README.md) and [day-4/CHANGES.md](day-4/CHANGES.md).

```bash
cd PoC/day-4
./run-day4-install.sh
```

### Day 4 highlights

1. **BBR pre-processing** — `payload-pre-processing` extracts `"model"` → `X-Gateway-Model-Name` before Kuadrant auth
2. **EnvoyFilter** — two-stage INSERT_BEFORE + INSERT_AFTER (tenant had post-only)
3. **HTTPRoutes** — `bbr-granite-4-tiny-gpu`, `bbr-facebook-opt-125m-simulated` in `llm` ns
4. **NeMo Guardrails** — `nemo-poc-config` + `nemo-poc-guardrails` in `redhat-ods-applications`
5. **Advanced Guardrails (optional track)** — scoped policy packs, bindings, provider registry — [09-advanced-guardrails-plan.md](09-advanced-guardrails-plan.md)
6. **Legacy cleanup** — scale `maas-api` in `maas-api` ns to 0; delete duplicate route

### Day 4 Exit Criteria

- [x] `POST /v1/chat/completions` returns 200 with API key + `"model"` in body
- [x] NeMo Guardrails Ready; blocked content returns `"status":"blocked"`
- [x] Legacy maas-api scaled to 0
- [ ] Auth 401 on unified path without key — use model paths for auth demo (see [day-4/CHANGES.md](day-4/CHANGES.md))
- [ ] Advanced Guardrails Demo A/B — after Day 6 persona keys: `./day-4/demo-advanced-guardrails.sh scoped|providers`
---

## Day 5: External LiteLLM Model Integration

**Goal:** Route inference to Red Hat workshop LiteLLM proxy via native `ExternalModel` CR.

**Status (2026-06-05):** Completed — see [day-5/README.md](day-5/README.md) and [day-5/CHANGES.md](day-5/CHANGES.md).

```bash
cd PoC/day-5
cp provider-key.env.example provider-key.env   # set LITELLM_PROVIDER_KEY
./run-day5-install.sh
```

### Day 5 highlights

1. **ExternalModel** — `codellama-7b-instruct` → `maas-rhdp.apps.maas.redhatworkshops.io`
2. **Provider secret** — `litellm-workshop-provider-key` with `inference.networking.k8s.io/bbr-managed=true`
3. **Governance** — model added to subscriptions + MaaSAuthPolicies
4. **HTTPRoute rewrite** — strip `/llm/codellama-7b-instruct` prefix for LiteLLM `/v1/...` paths
5. **Two-tier auth** — users send MaaS API keys; gateway injects workshop provider key

### Day 5 Exit Criteria

- [x] `POST .../llm/codellama-7b-instruct/v1/chat/completions` returns 200 with MaaS API key
- [x] No auth returns 401 on model path
- [x] Provider key not exposed to clients
- [ ] Unified BBR for external model — use model path (see [day-5/CHANGES.md](day-5/CHANGES.md))

---

## Day 6: Observability (COO) and Demo Personas

**Goal:** Install Cluster Observability Operator, enable showback telemetry, create per-user subscriptions/keys, seed daily traffic.

**Status (2026-06-05):** Completed — see [day-6/README.md](day-6/README.md) and [day-6/CHANGES.md](day-6/CHANGES.md).

```bash
cd PoC/day-6
./run-day6-install.sh
./daily-traffic.sh          # repeat daily until demo
```

### Day 6 highlights

1. **COO** — `cluster-observability-operator.v1.4.0` Succeeded
2. **RHOAI observability stack** — DSCI `metrics.storage` + OpenTelemetry operator → `data-science-perses` in `redhat-ods-monitoring`
3. **Perses dashboard** — `dashboard-3-maas-usage-admin` in RHOAI Console
4. **Datasource secret** — `kuadrant-prometheus-datasource-secret` for Kuadrant/Thanos queries
5. **Telemetry** — `maas-telemetry` with subscription/org/cost_center labels
6. **Demo personas** — retail, risk, platform subscriptions with distinct TPM limits
7. **Multi-user access** — htpasswd IdP + persona groups ([MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md))
8. **API keys** — minted per htpasswd user via `mint-persona-keys.sh` → `demo-users.env` (local, gitignored)
9. **Daily traffic** — `daily-traffic.sh` for ongoing metric seeding

Troubleshooting: [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md)

### Day 6 Exit Criteria

- [x] COO CSV Succeeded
- [x] OpenTelemetry operator Succeeded
- [x] `data-science-perses` Running
- [x] Perses MaaS dashboard + datasource Available
- [x] Three demo subscriptions Active with tokenMetadata
- [x] Per-persona API keys minted **as htpasswd users** (distinct `user` metric labels)
- [x] Daily traffic script returns HTTP 200 for all personas

---

## Day 7: OpenShift Lightspeed on MaaS (Optional)

**Goal:** Point OpenShift Lightspeed at the MaaS gateway so the platform consumes governed **Qwen3-4B-Instruct** inference (tool calling + cluster Q&A).

**Status (2026-06-05):** Completed — see [day-7/README.md](day-7/README.md) and [day-7/CHANGES.md](day-7/CHANGES.md).

```bash
cd PoC/day-7
./run-day7-install.sh
```

### Day 7 highlights

1. **Qwen on MaaS** — `MaaSModelRef` + BBR HTTPRoute for `qwen3-4b-instruct`
2. **OLSConfig** — provider `maas-gateway` (`openai` type) → `${MAAS_URL}/v1`, default model `qwen3-4b-instruct`
3. **Subscription** — `demo-openshift-lightspeed` (Qwen, 50k TPM/min)
4. **Secret** — `maas-gateway-api-key` in `openshift-lightspeed`
5. **Console** — Lightspeed icon → cluster questions answered via MaaS Qwen

> Qwen is pre-deployed with vLLM tool-calling flags (`hermes` parser). Granite tiny remains for other MaaS demos.

### Day 7 Exit Criteria

- [x] `qwen3-4b-instruct` MaaSModelRef Ready
- [x] `lightspeed-app-server` Ready
- [x] MaaS probe with Lightspeed key returns HTTP 200 (plain + tool_choice auto)
- [ ] Live console chat — manual verification

---

## Ready-State Exit Criteria (Final Checklist)

Before the client presentation:

| Check | Command / Validation |
|-------|---------------------|
| 3 GPUs allocatable | `oc get nodes ... GPUs` |
| MaaS enabled | `ModelsAsServiceReady=True` |
| Database connected | `maas-db-config` secret exists |
| Gateway programmed | `oc get gateway maas-default-gateway -n openshift-ingress` |
| Granite ready | 1+ replica on GPU node (`llm/granite-4-tiny-gpu`) |
| Simulator ready | CPU pod Running (`llm/facebook-opt-125m-simulated`) |
| Model refs | `oc get maasmodelref -n llm` |
| Subscriptions | `oc get maassubscription -n models-as-a-service` |
| Gateway inference | Model paths return 401/200/403 | Verified Day 3 |
| API keys | Basic + advanced keys exported | See day-3/demo-env.sh |
| Auth demo | 401 / 200 / 403 verified | Verified Day 3 |
| Rate limit demo | 429 on token burst | Verified Day 3 (13/16) |
| Guardrails (optional) | Blocked prompt returns `"status":"blocked"` | Verified Day 4 |
| Unified BBR | `/v1/chat/completions` with `"model"` field | Verified Day 4 |
| Legacy maas-api | 0 replicas in `maas-api` ns | Verified Day 4 (GitOps caveat) |
| External model | LiteLLM `codellama-7b-instruct` via gateway | Verified Day 5 |
| Observability (TP) | COO + Perses dashboard; per-user metrics | Verified Day 6 |
| Lightspeed (optional) | OLS → MaaS Qwen3-4B | Verified Day 7 |

---

## Transition Notes: Qwen to Granite

The existing Qwen deployment (`llm/qwen3-4b-instruct`) uses a tier-based auth model via GitOps. For the Granite demo:

- Qwen can coexist; it caused `setup-maas.sh` Phase 5 to skip — deploy Granite/simulator manually with `deploy-model.sh`
- Granite governance demos use `/v1/chat/completions` with `"model": "granite-4-tiny-gpu"`
- Simulator demos use `"model": "facebook-opt-125m-simulated"`
- If only 1 GPU remains for Granite, deploy with `replicas: 1` and defer Guardrails until spare GPU available

---

## Related Documents

- [03-cluster-validation-commands.md](03-cluster-validation-commands.md)
- [05-demonstration-steps.md](05-demonstration-steps.md)
- [06-troubleshooting.md](06-troubleshooting.md)
