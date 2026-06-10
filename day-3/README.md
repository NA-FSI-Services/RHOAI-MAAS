# Day 3 Installation Results

**Completed:** 2026-06-05T18:53:38Z  
**Duration:** ~15 minutes (Authorino TLS fix was the critical path)

---

## Summary

Day 3 exit criteria are **met**. The gateway blocker from Day 2 is resolved, API keys mint successfully, auth flows (401/200/403) and rate limiting (429) are verified, and `verify-maas.sh` reports **ALL CHECKS PASSED**.

| Criterion | Result |
|-----------|--------|
| Gateway inference (not 500) | **Pass** — 401 without key |
| API key minting | **Pass** |
| Auth 401 (no key) | **Pass** |
| Auth 200 (basic + simulator) | **Pass** |
| Auth 403 (basic + granite) | **Pass** |
| Auth 200 (advanced + granite) | **Pass** |
| Rate limit 429 | **Pass** — 13/16 requests rate-limited |
| `verify-maas.sh` full pass | **Pass** — 15/15 |
| Observability dashboard | **Pass** — already enabled |
| NeMo Guardrails | **Deferred** — not in guide repo; optional |
| Demo user groups | **Deferred Day 3** — added Day 1/6 via htpasswd ([MULTI-USER-ACCESS.md](../MULTI-USER-ACCESS.md)) |

---

## Root cause fix: Authorino TLS

Day 2 gateway HTTP 500 was caused by a **missing `authorino-server-cert`** TLS secret. The Authorino CR reported:

```
Ready=False: listener secret name authorino-server-cert not found
```

**Fix applied:**

```bash
oc apply -f manifests/02-platform-config/kuadrant/service-annotation.yaml
# Wait for secret (~10s)
oc patch authorino authorino -n kuadrant-system --type=merge ...
oc -n kuadrant-system set env deployment/authorino SSL_CERT_FILE=... REQUESTS_CA_BUNDLE=...
oc rollout restart deployment/authorino -n kuadrant-system
```

After fix: Authorino `Ready=True`, gateway returns **401** (not 500) on protected paths.

---

## What was executed

| Step | Action | Result |
|------|--------|--------|
| 1 | Authorino TLS serving cert | `authorino-server-cert` created; Authorino Ready |
| 2 | Legacy `maas-api` scale-down + route cleanup | Applied (GitOps may restore) |
| 3 | Kuadrant operator restart | Kuadrant Ready |
| 4 | Gateway smoke tests | health 200, models 401 |
| 5 | Mint API keys | `simulator-free`, `granite-tiny-gpu-premium` |
| 6 | Auth flow validation | 401 / 200 / 403 / 200 |
| 7 | Rate limit burst | 3×200, 13×429 |
| 8 | Observability dashboard patch | Already enabled |
| 9 | `verify-maas.sh --no-cleanup` | 15 passed, 0 failed |

---

## Demo API keys

Keys are stored locally in [demo-env.sh](demo-env.sh) for presenter use. **Do not commit this file.**

```bash
source day-3/demo-env.sh
# $MAAS_URL, $BASIC_USER_KEY, $ADVANCED_USER_KEY
```

Subscriptions used:

| Key | Subscription | Models |
|-----|--------------|--------|
| Basic | `simulator-free` | CPU simulator only |
| Advanced | `granite-tiny-gpu-premium` | Granite GPU |

---

## Inference URL and model ID reference

| Model | Gateway path | `"model"` in JSON body |
|-------|--------------|------------------------|
| Simulator | `${MAAS_URL}/llm/facebook-opt-125m-simulated/v1/chat/completions` | `facebook/opt-125m` |
| Granite | `${MAAS_URL}/llm/granite-4-tiny-gpu/v1/chat/completions` | `granite-4-tiny-gpu` |

> **Note:** Unified body-based routing at `${MAAS_URL}/v1/chat/completions` returns **404** on this cluster. Use model-specific paths above (see [CHANGES.md](CHANGES.md)).

---

## Auth flow results

```
A) No auth on simulator path          → HTTP 401
B) Basic key + simulator              → HTTP 200
C) Basic key + granite                → HTTP 403
D) Advanced key + granite             → HTTP 200
Rate limit (16 rapid requests)        → 3×200, 13×429
```

---

## File index

| File | Description |
|------|-------------|
| [CHANGES.md](CHANGES.md) | Plan deviations and resolutions |
| [run-day3-install.sh](run-day3-install.sh) | Repeatable Day 3 script |
| [day3-install.log](day3-install.log) | Full installation log |
| [demo-env.sh](demo-env.sh) | Exported API keys (local only) |
| [04-gateway-smoke.txt](04-gateway-smoke.txt) | Gateway HTTP codes after fix |
| [05-auth-flows.txt](05-auth-flows.txt) | Auth scenario results |
| [06-inference-tests.txt](06-inference-tests.txt) | Model ID discovery tests |
| [07-verify-and-rate-limit.log](07-verify-and-rate-limit.log) | verify-maas.sh output (15/15 pass) |
| [08-day3-final-state.txt](08-day3-final-state.txt) | Final cluster snapshot |

---

## PoC ready for presentation

The cluster is demo-ready for core MaaS governance scenarios (Demos 1–3 in [05-demonstration-steps.md](../05-demonstration-steps.md)), with model-specific URLs and corrected model IDs.

Optional items for future enhancement:

- NeMo Guardrails (requires separate manifests + GPU)
- Body-based `/v1/chat/completions` unified endpoint (WASM plugin route)
- Dedicated demo user accounts (cluster is admin-only)

---

## Compare to Day 2

| Metric | After Day 2 | After Day 3 |
|--------|-------------|-------------|
| Gateway `/v1/models` | HTTP 500 | **HTTP 401** |
| API key minting | Failed (AUTH_FAILURE) | **Working** |
| Inference | Blocked | **200** |
| Auth demos | Blocked | **401/200/403 verified** |
| Rate limit demo | Blocked | **429 verified** |
| verify-maas.sh | 9/12 pass | **15/15 pass** |
