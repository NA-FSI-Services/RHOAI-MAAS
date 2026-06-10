# Cluster Current State Assessment

> **Last updated:** 2026-06-05 (after Day 4 — **full PoC ready**)  
> **MaaS gateway:** derive with `https://maas.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')`

> **Day 6 complete:** COO installed, Perses MaaS dashboard live, three demo personas with per-user API keys. See [day-6/README.md](day-6/README.md).

---

## Summary

The cluster is **fully ready** for the MaaS governance demonstration including unified body-based routing and NeMo Guardrails content safety checks.

---

## Current vs Target State

| Area | Status |
|------|--------|
| MaaS platform (PostgreSQL, maas-api, models) | OK |
| Gateway auth (401/200/403/429 on model paths) | OK |
| Unified `/v1/chat/completions` BBR | OK (local models; external use model path) |
| NeMo Guardrails | OK — `nemo-poc-guardrails` Ready |
| External model (LiteLLM) | OK — `codellama-7b-instruct` via ExternalModel |
| Legacy maas-api (`maas-api` ns) | Scaled to 0 (GitOps may restore) |
| Observability dashboard | **COO installed** — Perses `dashboard-3-maas-usage-admin` (TP) |
| Demo personas (showback) | 3 subscriptions + **per-user** API keys — see [day-6/README.md](day-6/README.md), [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md) |
| OpenShift Lightspeed | MaaS gateway + Qwen3-4B — see [day-7/README.md](day-7/README.md) |

---

## Inference endpoints

| Use case | URL | `"model"` value |
|----------|-----|-----------------|
| Unified BBR (Demo 1) | `${MAAS_URL}/v1/chat/completions` | `facebook/opt-125m`, `granite-4-tiny-gpu`, or `qwen3-4b-instruct` |
| External model (Demo 7) | `${MAAS_URL}/llm/codellama-7b-instruct/v1/chat/completions` | `codellama-7b-instruct` |
| Auth demo (Demo 2) | `${SIM_URL}/v1/chat/completions` | `facebook/opt-125m` |
| Model listing | `${MAAS_URL}/v1/models` | (via maas-api) |

---

## NeMo Guardrails

| Resource | Namespace | Route |
|----------|-----------|-------|
| `NemoGuardrails/nemo-poc-guardrails` | `redhat-ods-applications` | `nemo-poc-guardrails-redhat-ods-applications.apps...` |

---

## Ready-State Exit Criteria

- [x] All Day 1–3 criteria
- [x] Unified body-based routing (`/v1/chat/completions`)
- [x] NeMo Guardrails deployed and blocking test content
- [x] Legacy duplicate maas-api scaled down
- [x] External model reachable via gateway with MaaS API key
- [x] COO + Perses MaaS observability dashboard
- [x] Per-user demo traffic personas configured (htpasswd users — [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md))
- [x] OpenShift Lightspeed configured to use MaaS gateway (optional)
- [ ] GitOps repo updated to permanently remove legacy maas-api (infra team)

---

## Related Documents

- [day-5/CHANGES.md](day-5/CHANGES.md) — Day 5 external model deviations
- [05-demonstration-steps.md](05-demonstration-steps.md) — updated presenter script
