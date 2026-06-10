# Day 4 Installation — Change Log and Deviations

**Date:** 2026-06-05  
**Script:** [run-day4-install.sh](run-day4-install.sh)

Records conflicts between the original PoC blueprint and live cluster behavior during Day 4.

---

## 1. Unified body-based routing — not enabled by default

| Original plan | Actual (Days 1–3) | Day 4 resolution |
|---------------|-------------------|------------------|
| Single `${MAAS_URL}/v1/chat/completions` with `"model"` in JSON | HTTP 404 | Deployed BBR pre-processing + header HTTPRoutes |

**Root cause:** Tenant reconcile deployed `payload-processing` (post-Kuadrant) but **not** `payload-pre-processing` (pre-Kuadrant), and the EnvoyFilter had only the INSERT_AFTER stage. Without pre-processing, Authorino never sees `X-Gateway-Model-Name` from the request body.

**Fix applied:**

1. Deploy `payload-pre-processing` (body-field-to-header plugin only)
2. Apply full two-stage [envoy-filter-full.yaml](manifests/bbr/envoy-filter-full.yaml)
3. Create BBR HTTPRoutes matching **path** `/v1/chat/completions` **and** header `X-Gateway-Model-Name`

**Image issue:** Upstream kustomize leaves `image: payload-processing` placeholder → `ImagePullBackOff`. Fixed with:

```bash
oc set image deployment/payload-pre-processing -n openshift-ingress \
  payload-pre-processing=quay.io/opendatahub/odh-ai-gateway-payload-processing:odh-stable
```

**URLRewrite issue:** Header-only HTTPRoutes with `ReplacePrefixMatch` produced malformed paths (`/v1/chat/completionsv1/chat/completions`). Fixed by combining path+header match and using `ReplaceFullPath: /v1/chat/completions`.

---

## 2. Auth on unified path vs model paths

| Endpoint | No API key | With API key |
|----------|------------|--------------|
| `/llm/.../v1/chat/completions` | **401** | 200 |
| `/v1/chat/completions` (BBR) | **200** (gap) | 200 |

Unified BBR HTTPRoutes route traffic to backends but **do not inherit the same Kuadrant auth enforcement** as KServe-generated routes in all cases. For live demos:

- Use API keys on unified endpoint (works with keys)
- Use model-specific paths for **401/403 auth demonstrations** (Demo 2)
- Optional future fix: attach per-route AuthPolicies via MaaSAuthPolicy controller or merge BBR routes into maas-controller reconciliation

---

## 3. NeMo Guardrails — not in rhoai-maas-guide

| Original plan | Actual | Resolution |
|---------------|--------|------------|
| Guardrails on GPU Node 3 with custom YAML from blueprint | No manifests in guide repo | Created PoC manifests from [RHOAI 3.4 Guardrails docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/enabling_ai_safety_with_guardrails/) |
| LLM self-check rails | CPU-only internal detectors sufficient for demo | ConfigMap uses Presidio + regex only (`OPENAI_API_KEY=not-used`) |
| GPU node placement | Not required for internal detectors | Deployed in `redhat-ods-applications` (no nodeSelector) |

**Demo model names in guardrails API:** `"model":"test"` (logging only; does not affect rail execution).

**Blocked content test:** `"My password is secret123"` → `"status":"blocked"` via regex rail.

---

## 4. Legacy maas-api GitOps restore

| Action | Result |
|--------|--------|
| Scale `maas-api` in `maas-api` ns to 0 | **Works temporarily** |
| Delete `HTTPRoute` + `AuthPolicy` in `maas-api` ns | **Works temporarily** |
| GitOps (ArgoCD) | **Restores** deployment + route within minutes |

Resources have `argocd.argoproj.io/tracking-id: models-as-a-service:...`.

**Permanent fix:** Remove legacy MaaS deployment from the GitOps `models-as-a-service` application. Operator-managed instance in `redhat-ods-applications:8443` is canonical.

**Day 4 mitigation:** Deprecation ConfigMap + scale-to-zero script step. Document for infra team.

---

## 5. payload-processing already present from Day 2

Day 2 tenant reconcile deployed post-processing BBR and `/v1/models` route to maas-api. Day 4 added the missing pre-processing half — not a full new install.

---

## 6. Day 4 exit criteria scorecard

| Criterion | Target | Result |
|-----------|--------|--------|
| NeMo Guardrails Ready | Ready | **Pass** |
| Guardrails block unsafe input | blocked status | **Pass** |
| Unified BBR inference | 200 with keys | **Pass** |
| payload-pre-processing Running | Running | **Pass** (after image fix) |
| Legacy maas-api removed | 0 replicas | **Pass** (GitOps may restore) |
| Auth 401 on unified path | 401 | **Fail** — use model paths for auth demo |
| Granite on GPU Node 3 for Guardrails | Optional | **N/A** — CPU detectors only |

---

## 7. Files updated in PoC package

| File | Change |
|------|--------|
| [04-installation-and-ready-state.md](../04-installation-and-ready-state.md) | Day 4 section |
| [02-cluster-current-state.md](../02-cluster-current-state.md) | Full PoC ready state |
| [05-demonstration-steps.md](../05-demonstration-steps.md) | Unified endpoint + Guardrails demo |
| [06-troubleshooting.md](../06-troubleshooting.md) | BBR pre-processing, URLRewrite, GitOps legacy |
| [README.md](../README.md) | Day 4 complete |
| [day-3/CHANGES.md](../day-3/CHANGES.md) | Cross-reference — BBR deferred to Day 4 |
