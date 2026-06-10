# Day 2 Installation — Change Log and Deviations

**Date:** 2026-06-05  
**Script:** [run-day2-install.sh](run-day2-install.sh)  
**Guide repo:** [../work/rhoai-maas-guide](../work/rhoai-maas-guide)

This document records conflicts between the original PoC plan and the live cluster during Day 2, and how they were resolved or deferred to Day 3.

---

## 1. setup-maas.sh Phase 5 skip (existing Qwen)

**Problem:** `setup-maas.sh --from-phase 3` completed Phases 3–4 but **skipped Phase 5** (model deployment) because an existing `LLMInferenceService` was found in the `llm` namespace (`qwen3-4b-instruct`).

**Resolution:** Manually ran:

```bash
./scripts/deploy-model.sh --model granite-tiny-gpu
./scripts/deploy-model.sh --model simulator
```

**Plan update:** On clusters with pre-existing models in `llm/`, always run `deploy-model.sh` explicitly after `setup-maas.sh`, or use `--from-phase 5` with a flag to force deploy. Documented in [04-installation-and-ready-state.md](../04-installation-and-ready-state.md).

---

## 2. Model names and namespaces (plan vs guide)

| Original plan | Actual (guide + cluster) | Resolution |
|---------------|-------------------------|------------|
| `granite-3-8b-instruct` (2 replicas, HF pull) | `granite-4-tiny-gpu` (1 replica, OCI modelcar) | Use `"model": "granite-4-tiny-gpu"` in demo curls |
| `local-simulator` | `facebook-opt-125m-simulated` | Use `"model": "facebook-opt-125m-simulated"` in demo curls |
| Models in `models-as-a-service` ns | LLMInferenceServices in **`llm`** ns | Subscriptions/auth policies stay in `models-as-a-service`; model pods in `llm` |
| MaaSModelRef in `models-as-a-service` | MaaSModelRef in **`llm`** ns | Guide convention; update validation commands |

**Demo model field mapping:**

| Demo tier | `"model"` value in JSON body |
|-----------|------------------------------|
| Basic (simulator) | `facebook-opt-125m-simulated` |
| Advanced (Granite) | `granite-4-tiny-gpu` |

---

## 3. Full DSC apply on GitOps cluster

**Problem:** `setup-maas.sh` Phase 4 applied the full guide DSC kustomize (`manifests/03-rhoai-config/`), enabling components beyond MaaS:

- `ray`, `feast`, `aipipelines`, `trainer`, `workbenches`, etc.

**Result:** DSC overall phase changed from **Ready** to **Not Ready** while those components provision. `ModelsAsServiceReady` remained **True**.

**Resolution for Day 2:** Accepted — MaaS platform is functional. For production GitOps clusters, prefer a **targeted patch** instead of full DSC apply:

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

**Day 3 optional:** Revert unnecessary component enables if they cause resource contention.

---

## 4. Duplicate maas-api deployments (GitOps conflict)

**Problem:** Two `maas-api` deployments coexist:

| Deployment | Namespace | Port | DB | Source |
|------------|-----------|------|-----|--------|
| Legacy GitOps | `maas-api` | 8080 | No | Pre-existing ArgoCD |
| Operator-managed | `redhat-ods-applications` | 8443 | Yes | Day 2 setup-maas.sh |

Both had `HTTPRoute/maas-api-route` and `MaaSAuthPolicy` resources, causing ambiguous gateway routing.

**Partial remediation:**

```bash
oc delete httproute maas-api-route -n maas-api
```

**Result:** `/maas-api/health` → HTTP 200 (routes to operator-managed API). Model inference paths still HTTP 500.

**Day 3 action:** Scale down or remove legacy deployment:

```bash
oc scale deployment maas-api -n maas-api --replicas=0
# Or delete if GitOps allows:
# oc delete deployment maas-api -n maas-api
```

---

## 5. Gateway HTTP 500 on model paths (open blocker)

**Problem:** After MaaS platform and models are Ready, gateway returns:

- `GET /v1/models` → **HTTP 500**
- `GET /llm/granite-4-tiny-gpu/v1/models` → **HTTP 500**
- `GET /maas-api/health` → **HTTP 200** (after route fix)

Gateway pod logs show Authorino gRPC errors (`gRPC status code is not OK`).

**Attempted fixes (Day 2):**

- Deleted legacy `HTTPRoute` in `maas-api` namespace
- Restarted gateway pod
- Restarted Kuadrant operator

**Impact:** `verify-maas.sh` fails at API key creation (Internal Server Error). Auth and rate-limit tests skipped.

**Day 3 remediation plan:**

1. Apply `service-annotation.yaml` to generate `authorino-server-cert` (**root cause fix** — see [day-3/CHANGES.md](../day-3/CHANGES.md))
2. Remove legacy `maas-api` deployment and duplicate AuthPolicies
3. Restart Authorino + verify TLS bootstrap annotation
4. Re-run `./scripts/verify-maas.sh`

See [../06-troubleshooting.md](../06-troubleshooting.md#gateway-http-500-on-model-paths-authorino-grpc).

---

## 6. MaaSSubscription transient Failed state

**Problem:** Subscriptions showed **Failed** immediately after apply (08-day2-summary.txt).

**Resolution:** Self-healed within ~12 minutes to **Active** once `maas-api` connected to PostgreSQL and MaaSModelRefs reached Ready.

**Note:** Expect brief Failed → Active transition during reconcile; do not delete and re-apply unless stuck >15 min.

---

## 7. Granite replica count

| Original plan | Actual | Resolution |
|---------------|--------|------------|
| 2 replicas on 2 GPU nodes | 1 replica on 1 GPU node | Sufficient for PoC; optional scale-up in Day 3 if gateway fixed |

```bash
# Optional — only if gateway healthy and spare GPU available
oc patch llminferenceservice granite-4-tiny-gpu -n llm --type=merge -p '{"spec":{"replicas":2}}'
```

Qwen occupies one GPU; 2 Granite replicas would require scaling Qwen down or using 2 of 3 GPUs.

---

## 8. Day 2 exit criteria scorecard

| Criterion | Target | Result |
|-----------|--------|--------|
| `ModelsAsServiceReady=True` | True | **Pass** |
| `maas-db-config` secret | Present | **Pass** |
| `maas-api` healthy | Running + DB | **Pass** (operator instance) |
| Granite Ready | 1+ replica | **Pass** (1 replica) |
| Simulator on CPU | Running | **Pass** |
| MaaSModelRef applied | granite + simulator | **Pass** |
| MaaSSubscription Active | Applied | **Pass** |
| Gateway inference working | 200/401 flows | **Fail** — HTTP 500 |
| API key minting | Working | **Fail** — blocked by 500 |
| verify-maas.sh full pass | All phases | **Fail** — 9/12 checks |

---

## 9. Files updated in PoC package

| File | Change |
|------|--------|
| [04-installation-and-ready-state.md](../04-installation-and-ready-state.md) | Day 2 status, model names, namespace corrections, exit criteria |
| [02-cluster-current-state.md](../02-cluster-current-state.md) | Post-Day-2 state, updated gap analysis |
| [05-demonstration-steps.md](../05-demonstration-steps.md) | Model names, namespace references |
| [06-troubleshooting.md](../06-troubleshooting.md) | Duplicate maas-api, gateway 500, Phase 5 skip |
| [README.md](../README.md) | Day 2 status and index entry |
| [03-cluster-validation-commands.md](../03-cluster-validation-commands.md) | Model names in curl examples |
