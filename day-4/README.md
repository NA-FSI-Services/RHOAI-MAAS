# Day 4 Installation Results

**Completed:** 2026-06-05T19:10:12Z  
**Duration:** ~10 minutes (after HTTPRoute rewrite fix)

---

## Summary

Day 4 implements the three remaining blueprint items: **NeMo Guardrails**, **unified body-based routing**, and **legacy maas-api cleanup**.

| Criterion | Result |
|-----------|--------|
| NeMo Guardrails deployed | **Pass** — `nemo-poc-guardrails` Ready |
| Guardrails safe content | **Pass** — `status: success` |
| Guardrails blocked content | **Pass** — `status: blocked` (regex on "password") |
| Unified `/v1/chat/completions` (BBR) | **Pass** — HTTP 200 with API keys |
| BBR simulator via body `"model"` | **Pass** — `facebook/opt-125m` |
| BBR granite via body `"model"` | **Pass** — `granite-4-tiny-gpu` |
| payload-pre-processing | **Pass** — after image fix |
| Legacy maas-api scaled to 0 | **Pass** (GitOps may restore — see CHANGES) |
| Unified path without auth | **Fail** — HTTP 200 (model paths still 401) |

---

## What was executed

| Step | Action | Result |
|------|--------|--------|
| 1 | Deploy `payload-pre-processing` + full two-stage EnvoyFilter | Pre-proc Running; extracts `X-Gateway-Model-Name` |
| 2 | Apply header+path BBR HTTPRoutes in `llm` namespace | Unified endpoint works |
| 3 | Scale legacy `maas-api` to 0; delete duplicate route/auth | Cleaned (GitOps restores periodically) |
| 4 | Deploy NeMo Guardrails ConfigMap + CR | Ready in ~20s |
| 5 | Validate inference + guardrails checks | See [05-validation-retry.txt](05-validation-retry.txt) |

---

## Unified body-based routing

After Day 4, use the **single front door** endpoint:

```bash
source day-3/demo-env.sh

# Simulator (basic key)
curl -s -X POST "${MAAS_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${BASIC_USER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Hello"}],"max_tokens":20}'

# Granite (advanced key)
curl -s -X POST "${MAAS_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${ADVANCED_USER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"granite-4-tiny-gpu","messages":[{"role":"user","content":"Hello"}],"max_tokens":30}'
```

Model-specific paths (`/llm/.../v1/chat/completions`) remain valid and enforce auth correctly (401 without key).

---

## NeMo Guardrails

```bash
export GUARDRAILS_URL="https://$(oc get route nemo-poc-guardrails -n redhat-ods-applications -o jsonpath='{.spec.host}')"

# Safe content
curl -sk -X POST "${GUARDRAILS_URL}/v1/guardrail/checks" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"What is the capital of France?"}]}'

# Blocked content (password keyword)
curl -sk -X POST "${GUARDRAILS_URL}/v1/guardrail/checks" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"My password is secret123"}]}'
```

Expected: safe → `"status":"success"`; blocked → `"status":"blocked"`.

---

## File index

| File | Description |
|------|-------------|
| [CHANGES.md](CHANGES.md) | Plan deviations and resolutions |
| [run-day4-install.sh](run-day4-install.sh) | Repeatable Day 4 script |
| [day4-install.log](day4-install.log) | Full installation log |
| [05-validation-retry.txt](05-validation-retry.txt) | Final validation (BBR + Guardrails) |
| [06-day4-final-state.txt](06-day4-final-state.txt) | Cluster snapshot |
| [manifests/bbr/](manifests/bbr/) | BBR EnvoyFilter, HTTPRoutes, pre-processing |
| [manifests/nemo-guardrails/](manifests/nemo-guardrails/) | ConfigMap + NemoGuardrails CR |
| [manifests/legacy-maas-api-cleanup.yaml](manifests/legacy-maas-api-cleanup.yaml) | Deprecation marker ConfigMap |

---

## PoC status

The sandbox now supports:

- Full MaaS governance (Days 1–3)
- Unified `/v1/chat/completions` body-based routing (Day 4)
- NeMo Guardrails content checks (Day 4, Technology Preview)
- Canonical operator-managed `maas-api` only (legacy scaled down)

See [CHANGES.md](CHANGES.md) for auth gap on unified path and GitOps legacy restore notes.
