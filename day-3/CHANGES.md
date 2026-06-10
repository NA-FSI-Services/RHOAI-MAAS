# Day 3 Installation — Change Log and Deviations

**Date:** 2026-06-05  
**Script:** [run-day3-install.sh](run-day3-install.sh)

Records conflicts between the original PoC plan and live cluster behavior during Day 3, and how they were resolved.

---

## 1. Gateway HTTP 500 — root cause identified (critical)

| Original diagnosis (Day 2) | Actual root cause | Resolution |
|----------------------------|-------------------|------------|
| Duplicate maas-api, Kuadrant stale reconcile | **Missing `authorino-server-cert` TLS secret** | Apply `service-annotation.yaml`; restart Authorino |

The Authorino CR was `Ready=False` with message `TlsSecretNotProvided`. Gateway WASM plugin could not reach Authorino over gRPC, causing HTTP 500 on all authenticated routes.

The `service-annotation.yaml` manifest (Day 1 platform config) was **never applied** on this cluster. Day 1 only applied the gateway TLS bootstrap annotation, not the Authorino serving-cert annotation.

**Permanent fix for runbook:** Add to Day 1 or Day 2 prerequisites:

```bash
oc apply -f manifests/02-platform-config/kuadrant/service-annotation.yaml
oc wait --for=jsonpath='{.type}'=kubernetes.io/tls secret/authorino-server-cert -n kuadrant-system --timeout=120s
```

Duplicate maas-api cleanup helped `/maas-api/health` routing but did **not** fix the 500 alone.

---

## 2. Body-based routing at `/v1/chat/completions` (plan vs reality)

| Original plan | Actual cluster | Resolution |
|---------------|----------------|------------|
| Single endpoint `${MAAS_URL}/v1/chat/completions` with `"model"` field | Returns **HTTP 404** (Day 3) | **Resolved Day 4** — see [day-4/README.md](../day-4/README.md) |

Working inference URLs (Day 3 fallback; still used for auth demos):

```
POST ${MAAS_URL}/llm/facebook-opt-125m-simulated/v1/chat/completions
POST ${MAAS_URL}/llm/granite-4-tiny-gpu/v1/chat/completions
```

Day 3: unified path required additional BBR pre-processing not deployed by tenant reconcile. **Day 4** deployed `payload-pre-processing`, two-stage EnvoyFilter, and header+path HTTPRoutes. Use unified endpoint for routing demo; model-specific paths for 401/403 auth demo (unified path auth gap — see [day-4/CHANGES.md](../day-4/CHANGES.md)).

---

## 3. Model ID in JSON body (plan vs API)

| Original plan | Actual vLLM model ID | Resolution |
|---------------|---------------------|------------|
| `"model": "local-simulator"` | `"model": "facebook/opt-125m"` | Updated demo curls |
| `"model": "granite-3-8b-instruct"` | `"model": "granite-4-tiny-gpu"` | Updated demo curls |

Model IDs come from `GET .../v1/models` response, not from LLMInferenceService resource names.

---

## 4. Demo user groups (skipped)

| Original plan | Actual cluster | Resolution |
|---------------|----------------|------------|
| `basic-users-group`, `advanced-users-group` with demo users | Admin-only sandbox; no HTPasswd users | Use API keys tied to subscriptions |

Guide subscriptions use `system:authenticated` as owner group. API keys are minted by cluster-admin via `POST /maas-api/v1/api-keys` with subscription name:

- Basic: `simulator-free`
- Advanced: `granite-tiny-gpu-premium`

No `oc adm groups` commands were run — not applicable without identity provider users.

---

## 5. Legacy maas-api GitOps reconciliation

| Action | Result |
|--------|--------|
| Scaled `maas-api` in `maas-api` ns to 0 | GitOps restored to 1/1 within minutes |
| Deleted `HTTPRoute/maas-api-route` in `maas-api` | Recreated by ArgoCD |

After Authorino fix, gateway works **even with legacy maas-api restored**. Long-term: update GitOps repo to remove legacy MaaS deployment or point it to operator-managed instance.

---

## 6. NeMo Guardrails (deferred)

| Original plan | Actual | Resolution |
|---------------|--------|------------|
| Deploy Guardrails on GPU Node 3 | No manifests in `rhoai-maas-guide` repo | Deferred — optional demo |

TrustyAI operator is Managed in DSC. Guardrails deployment requires separate CR manifests from RHOAI docs, not included in the guide automation. Spare GPU node available (ip-10-0-85-158) if needed later.

---

## 7. Observability dashboard

| Original plan | Actual | Resolution |
|---------------|--------|------------|
| Patch to enable TP dashboard | Already `observabilityDashboard=true` | No change needed |

Likely enabled by full DSC apply on Day 2.

---

## 8. Day 3 exit criteria scorecard

| Criterion | Target | Result |
|-----------|--------|--------|
| Fix gateway 500 | 401/200 flows | **Pass** |
| Mint API keys | 2 keys | **Pass** |
| Auth 401 | Unauthorized blocked | **Pass** |
| Auth 200 | Basic + simulator | **Pass** |
| Auth 403 | Basic + granite denied | **Pass** |
| Auth 200 | Advanced + granite | **Pass** |
| Rate limit 429 | Burst triggers limit | **Pass** (13/16) |
| verify-maas.sh | All phases | **Pass** (15/15) |
| NeMo Guardrails | Optional | **Deferred** |
| Demo user groups | Optional | **Skipped** |

---

## 9. Files updated in PoC package

| File | Change |
|------|--------|
| [04-installation-and-ready-state.md](../04-installation-and-ready-state.md) | Day 3 complete; Authorino TLS prerequisite |
| [02-cluster-current-state.md](../02-cluster-current-state.md) | Demo-ready state |
| [05-demonstration-steps.md](../05-demonstration-steps.md) | Model IDs, model-specific URLs |
| [06-troubleshooting.md](../06-troubleshooting.md) | Authorino TLS root cause section |
| [README.md](../README.md) | PoC complete status |
| [day-1/CHANGES.md](../day-1/CHANGES.md) | Cross-reference Authorino cert gap |
