# 15-Minute Demo Recap

Presenter cheat sheet for a short recap of prior MaaS demos. Use this **after** the cluster is ready ([04-installation-and-ready-state.md](04-installation-and-ready-state.md) / [08-rhoai-3.5-ea-install.md](08-rhoai-3.5-ea-install.md)).

Full runbooks (40–70 minutes): [05-demonstration-steps.md](05-demonstration-steps.md) (terminal), [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md) (RHOAI UI).

**Story:** one governed front door for three LOB teams — who can call which model, how much they can spend, what gets blocked, and how finance sees the bill.

**Mode:** UI-first. Keep a terminal tab minimized for **401 / 403** and Guardrails proofs only.

> **Catalog note:** This 3.5-ea lab does **not** serve Granite or CodeLlama. Treat **Llama 3.1 8B Instruct** as the GPU / premium stand-in (retail denied) and **Llama 3.1 70B** as the external stand-in. Older docs still mention `granite-4-tiny-gpu` and `codellama-7b-instruct`.

---

## Live catalog

Derive URLs; do not hardcode hostnames:

```bash
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
export MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
export SIM_URL="${MAAS_URL}/llm/facebook-opt-125m-simulated"
export GPU_URL="${MAAS_URL}/llm/llama-3-1-8b-instruct"
export EXT_URL="${MAAS_URL}/llm/llama-31-70b-cpu"
export GUARDRAILS_URL="https://$(oc get route nemo-poc-guardrails -n redhat-ods-applications -o jsonpath='{.spec.host}')"
source day-3/demo-env.sh
source day-6/demo-users.env
```

| Model | Role in recap | Path | JSON `"model"` | Kind |
|-------|---------------|------|----------------|------|
| Facebook OPT 125M (simulated) | CPU sandbox — retail allowed | `/llm/facebook-opt-125m-simulated` | `facebook/opt-125m` | Local |
| Llama 3.1 8B Instruct | GPU premium — **retail denied** | `/llm/llama-3-1-8b-instruct` | `llama-3-1-8b-instruct` | Local GPU |
| Llama 3.1 70B (workshop) | External / hybrid | `/llm/llama-31-70b-cpu` | `llama-31-70b-cpu` | `ExternalModel` |

Skip unless asked: `gemma-4-e4b-it`, `qwen36-fp8`, OpenShift Lightspeed.

### Personas

| Persona | htpasswd user | Subscription | Models | TPM highlight | Cost center |
|---------|---------------|--------------|--------|---------------|-------------|
| Retail Analyst | `demo-retail-analyst` | `demo-retail-analyst` | Simulator + 70B external | 3,000 / min | `CC-RETAIL-1001` |
| Risk Analytics | `demo-risk-analyst` | `demo-risk-analytics` | **Llama 8B** + 70B external | 80,000 / min on 8B | `CC-RISK-2001` |
| Platform Ops | `demo-platform-ops` | `demo-platform-ops` | All three | 10k–25k / min | `CC-PLATFORM-3001` |

---

## Pre-flight (before the room fills)

```bash
oc whoami --show-server
./day-6/daily-traffic.sh --quick
```

- [ ] `maas-default-gateway` Programmed
- [ ] Simulator, Llama 8B, and 70B external **Ready**
- [ ] Demo subscriptions **Active**; persona keys loaded (`demo-users.env`)
- [ ] **Observe & monitor → Dashboard** loads (not Service Unavailable)
- [ ] Daily traffic seed returned **HTTP 200** on sim / GPU / external
- [ ] Retail **403** on Llama 8B still works (see [Catch-all free tiers](#catch-all-free-tiers) if it returns 200)

**Tabs:** RHOAI AI Console (admin) → Gen AI studio + Settings + Observe; OpenShift Console in reserve; terminal with proofs pasted.

---

## Clock

| Min | Prior demo | Show | Line to land |
|-----|------------|------|----------------|
| **0–1** | Frame | One URL, three personas | Platform publishes once; LOB teams never get a raw model URL or provider key |
| **1–3** | Demo 1 — gateway | **Gen AI studio → AI asset endpoints**: simulator, Llama 8B, 70B external | Same `maas.` hostname; GPU vs CPU vs external |
| **3–7** | Demo 2 — AuthZ | **Settings → Subscriptions + Authorization policies**, then three curls | **401** no key, **403** retail on 8B, **200** risk on 8B |
| **7–9** | Demo 3 — TPM | Retail 3k vs Risk 80k in subscription details | Limits are **tokens**, not HTTP request counts |
| **9–11** | Demo 5 — Guardrails | Safe vs blocked check | `"password"` blocked before the LLM |
| **11–13** | Demo 7 — external | 70B in the same catalog | Hybrid routing; provider key stays in a cluster Secret |
| **13–15** | Demo 6 — showback | **Observe & monitor → Dashboard** — three users / cost centers | Usage is `demo-retail-analyst`, not `admin` |

---

## Talking points (keep these seven)

1. **Single front door** — apps call the gateway; payload pre-processing + Kuadrant pick the backend from the JSON `model` field.
2. **Zero trust at the edge** — no key never reaches the pod (**401**); wrong subscription is **403**, not a model error.
3. **Declarative entitlements** — Llama 8B lockdown is subscription/policy, not `system:authenticated`.
4. **Token economics** — TPM protects GPU KV-cache; request-count limits would miss one huge prompt.
5. **Content safety** — NeMo Guardrails (TP) is a separate check path (`nemo-poc-guardrails`).
6. **Hybrid without shadow keys** — workshop 70B uses a MaaS key; the provider key is injected from a Secret.
7. **Showback** — `tokenMetadata` (org + cost center) plus per-user minted keys so finance can attribute usage.

---

## Proofs (terminal, model-specific paths)

Use **model-specific** URLs for 401/403. Do not use unified `/v1/chat/completions` for auth proofs.

```bash
source day-3/demo-env.sh
source day-6/demo-users.env
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
export MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
export SIM_URL="${MAAS_URL}/llm/facebook-opt-125m-simulated"
export GPU_URL="${MAAS_URL}/llm/llama-3-1-8b-instruct"
export EXT_URL="${MAAS_URL}/llm/llama-31-70b-cpu"
export GUARDRAILS_URL="https://$(oc get route nemo-poc-guardrails -n redhat-ods-applications -o jsonpath='{.spec.host}')"
```

### Auth — 401 / 403 / 200

```bash
# 401 — no API key
curl -sk -o /dev/null -w "no-auth: %{http_code}\n" -X POST "${SIM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Ping"}],"max_tokens":5}'

# 403 — retail denied Llama 8B
curl -sk -o /dev/null -w "retail→8B: %{http_code}\n" -X POST "${GPU_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_RETAIL_KEY}" -H "Content-Type: application/json" \
  -d '{"model":"llama-3-1-8b-instruct","messages":[{"role":"user","content":"Hello"}],"max_tokens":8}'

# 200 — risk allowed Llama 8B
curl -sk -o /dev/null -w "risk→8B: %{http_code}\n" -X POST "${GPU_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_RISK_KEY}" -H "Content-Type: application/json" \
  -d '{"model":"llama-3-1-8b-instruct","messages":[{"role":"user","content":"Hello"}],"max_tokens":8}'
```

**Expected:** `no-auth: 401`, `retail→8B: 403`, `risk→8B: 200`.

### Guardrails — safe vs blocked

```bash
curl -sk -X POST "${GUARDRAILS_URL}/v1/guardrail/checks" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -d '{"model":"test","messages":[{"role":"user","content":"What is compound interest?"}]}' | jq -r .status

curl -sk -X POST "${GUARDRAILS_URL}/v1/guardrail/checks" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -d '{"model":"test","messages":[{"role":"user","content":"My password is secret123"}]}' | jq -r .status
```

**Expected:** `success` then `blocked`.

### Optional — external 200 (if Demo 7 needs a live call)

```bash
curl -sk -o /dev/null -w "retail→70B: %{http_code}\n" -X POST "${EXT_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_RETAIL_KEY}" -H "Content-Type: application/json" \
  -d '{"model":"llama-31-70b-cpu","messages":[{"role":"user","content":"Hello"}],"max_tokens":8}'
```

**Expected:** `200`. Use the **model-specific** path — unified BBR does not inject the provider key for external models on this cluster.

---

## Skip in 15 minutes (reserve)

| Topic | Why skip | If asked |
|-------|----------|----------|
| Demo 4 — EPP / multi-replica | Not in RHOAI UI | OpenShift pods in `llm` |
| Day 7 Lightspeed | Optional closer | OpenShift header chat uses MaaS Llama 8B |
| Unified body-based `/v1/chat/completions` | Playground uses per-model URLs | [05 Demo 1](05-demonstration-steps.md#demo-1-enterprise-ai-gateway--model-routing) |
| Persona playground switch | Needs dedicated projects + 3.5-ea playground workaround | [07 Step 0.1](07-ui-based-demonstration-steps.md#step-01--create-rhoai-projects-before-playground) |
| **429** TPM proof | Needs two rapid large curls | [05 Demo 3](05-demonstration-steps.md#demo-3-token-based-rate-limiting) — show limits in UI instead |

---

## Catch-all free tiers

Retail **403** on Llama 8B fails (returns **200**) if `llama-3-1-8b-instruct-free` still lists `system:authenticated`. Restrict free tiers before presenting:

```bash
oc apply -f day-6/manifests/client-test-restrict-free-subscriptions.yaml
```

Do not grant playground RBAC on shared namespaces (for example `grafana`). Each persona uses a dedicated RHOAI project.

If a basic-tier key returns **403** on the simulator instead of 200, remint Day 3 keys: `./day-3/remint-demo-keys.sh`.

Dashboard empty or Service Unavailable: [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md) and `./day-6/daily-traffic.sh --quick`.

---

## Related documents

- [05-demonstration-steps.md](05-demonstration-steps.md) — full terminal presenter script
- [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md) — full RHOAI UI presenter script
- [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md) — htpasswd personas and per-user API keys
- [day-6/README.md](day-6/README.md) — COO + daily traffic
- [06-troubleshooting.md](06-troubleshooting.md) — live recovery
