# Day 2 Installation Results

**Completed:** 2026-06-05T18:41:08Z  
**Duration:** ~45 minutes (includes model pull, MaaS reconcile, routing remediation)

---

## Summary

Day 2 **partially meets** exit criteria. The MaaS control plane, database, models, and governance CRs are in place, but **gateway inference paths return HTTP 500** — blocking API key minting and auth demos until Day 3 remediation.

| Criterion | Result |
|-----------|--------|
| `ModelsAsServiceReady=True` | **Pass** |
| PostgreSQL + `maas-db-config` | **Pass** |
| `maas-api` healthy (internal) | **Pass** — operator-managed in `redhat-ods-applications:8443` |
| Granite Ready | **Pass** — 1 replica (`granite-4-tiny-gpu`) on GPU node |
| CPU simulator Ready | **Pass** — `facebook-opt-125m-simulated` on CPU worker |
| `MaaSModelRef` Ready | **Pass** — granite + simulator |
| `MaaSSubscription` Active | **Pass** — 5 subscriptions (4 guide + verify script) |
| Gateway `/v1/models` | **Fail** — HTTP 500 (Authorino gRPC) |
| Gateway `/v1/chat/completions` | **Blocked** — requires Day 3 fix + API keys |
| Granite 2/2 replicas | **Deferred** — single replica sufficient for g6e demo |

---

## What was executed

1. **`setup-maas.sh --from-phase 3 --model granite-tiny-gpu --skip-verify`**
   - Phase 3: PostgreSQL, DB secrets, Authorino TLS patch
   - Phase 4: Full guide DSC apply (`modelsAsService: Managed`), `maas-api` in `redhat-ods-applications`
   - Phase 5: **Skipped** by script (existing Qwen in `llm/` namespace)

2. **Manual model deployment** (because Phase 5 was skipped)
   - `./scripts/deploy-model.sh --model granite-tiny-gpu`
   - `./scripts/deploy-model.sh --model simulator`

3. **Routing remediation**
   - Deleted legacy GitOps `HTTPRoute/maas-api-route` in `maas-api` namespace (was routing to old `maas-api:8080` without DB)
   - After fix: `/maas-api/health` → HTTP 200; model paths still HTTP 500

4. **Verification**
   - `./scripts/verify-maas.sh --no-cleanup` — 9 passed, 3 failed (API key creation, auth, rate limit)

---

## Cluster state after Day 2

### Models (`llm` namespace)

| LLMInferenceService | Ready | Node | Type |
|---------------------|-------|------|------|
| `granite-4-tiny-gpu` | True | ip-10-0-40-203 | GPU (g6e.2xlarge) |
| `facebook-opt-125m-simulated` | True | ip-10-0-27-212 | CPU |
| `qwen3-4b-instruct` | True | ip-10-0-20-178 | GPU (pre-existing) |

### MaaS CRs

| Resource | Namespace | Phase |
|----------|-----------|-------|
| `MaaSModelRef/granite-4-tiny-gpu` | `llm` | Ready |
| `MaaSModelRef/facebook-opt-125m-simulated` | `llm` | Ready |
| `MaaSSubscription/*` (5) | `models-as-a-service` | Active |
| `Tenant/default-tenant` | `models-as-a-service` | Ready |

### MaaS platform

| Component | Namespace | Status |
|-----------|-----------|--------|
| PostgreSQL | `redhat-ods-applications` | Running |
| `maas-api` (operator) | `redhat-ods-applications` | Running (8443, DB connected) |
| `maas-api` (legacy GitOps) | `maas-api` | Running (8080, no DB) — **remove in Day 3** |
| DSC phase | — | **Not Ready** (ray, feast, trainer provisioning from full DSC apply) |
| `ModelsAsServiceReady` | — | **True** |

### Gateway smoke tests

```
GET /maas-api/health              → HTTP 200
GET /v1/models                    → HTTP 500
GET /llm/granite-4-tiny-gpu/v1/models → HTTP 500
POST /v1/chat/completions (no auth)   → HTTP 404
```

---

## File index

| File | Description |
|------|-------------|
| [CHANGES.md](CHANGES.md) | Plan deviations and conflict resolutions |
| [run-day2-install.sh](run-day2-install.sh) | Repeatable Day 2 script |
| [day2-install.log](day2-install.log) | Full installation log |
| [11-day2-final-state.txt](11-day2-final-state.txt) | Final cluster state snapshot |
| [10-verify-maas.log](10-verify-maas.log) | `verify-maas.sh` output (9 pass / 3 fail) |
| [09-routing-fix.txt](09-routing-fix.txt) | Legacy HTTPRoute deletion results |
| [07-gateway-smoke-tests-final.txt](07-gateway-smoke-tests-final.txt) | Gateway curl results after routing fix |
| [08-day2-summary.txt](08-day2-summary.txt) | Mid-install summary (before models Ready) |
| [00-state-before.txt.txt](00-state-before.txt.txt) | Pre-install snapshot |
| [01-dsc-status.txt.txt](01-dsc-status.txt.txt) | DSC YAML after apply |
| [02-maas-db.txt.txt](02-maas-db.txt.txt) | PostgreSQL and secrets |
| [03-maas-api.txt.txt](03-maas-api.txt.txt) | Both maas-api deployments |
| [04-maas-crs.txt.txt](04-maas-crs.txt.txt) | MaaS CRs (early reconcile) |
| [05-llminferenceservices.txt.txt](05-llminferenceservices.txt.txt) | LLMInferenceServices |
| [06-pods-llm.txt.txt](06-pods-llm.txt.txt) | Model pods |

---

## Next step: Day 3

Day 3 must resolve the gateway 500 before auth/rate-limit demos:

1. Remove or scale down legacy `maas-api` in `maas-api` namespace
2. Investigate Authorino gRPC errors on model HTTPRoutes (Kuadrant restart, TLS, duplicate AuthPolicies)
3. Create user groups and mint API keys
4. Run `./scripts/verify-maas.sh` to full pass
5. Optional: NeMo Guardrails, observability dashboard

See [../04-installation-and-ready-state.md](../04-installation-and-ready-state.md) Day 3 section and [CHANGES.md](CHANGES.md).

---

## Compare to Day 1

| Metric | After Day 1 | After Day 2 |
|--------|-------------|-------------|
| `modelsAsService` | Removed | **Managed** |
| PostgreSQL | Not present | **Running** |
| `maas-api` (with DB) | Not present | **Running** in `redhat-ods-applications` |
| Granite model | Not deployed | **Ready** (`granite-4-tiny-gpu`) |
| Simulator | Not deployed | **Ready** (`facebook-opt-125m-simulated`) |
| MaaSModelRef | None | **2 Ready** |
| MaaSSubscription | None | **5 Active** |
| Gateway inference | 503/401 | **500** (health OK) |
