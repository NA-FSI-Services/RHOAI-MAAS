# Live Demonstration Steps

Presenter runbook for the RHOAI 3.4 MaaS PoC. Execute **after** completing [04-installation-and-ready-state.md](04-installation-and-ready-state.md).

> **Client-facing UI demo:** For RHOAI Console–first presentation with screenshot placeholders, use [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md).

**Total estimated time:** 40–50 minutes (core demos 1–3 + 7); 60–70 minutes with optional demos 4–6.

---

## Pre-Demo Setup

### Environment variables

```bash
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
# ingress domain already includes "apps." on this cluster (e.g. apps.ocp.example.com)
export MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
export UNIFIED_URL="${MAAS_URL}/v1/chat/completions"
export SIM_URL="${MAAS_URL}/llm/facebook-opt-125m-simulated"
export GRAN_URL="${MAAS_URL}/llm/granite-4-tiny-gpu"
export EXT_URL="${MAAS_URL}/llm/codellama-7b-instruct"
export GUARDRAILS_URL="https://$(oc get route nemo-poc-guardrails -n redhat-ods-applications -o jsonpath='{.spec.host}')"

# Day 3 tier keys (Demo 2 Scenarios B/C) — remint if expired: ./day-3/remint-demo-keys.sh
source day-3/demo-env.sh
# BASIC_USER_KEY, ADVANCED_USER_KEY

# Multi-user persona keys (Day 1 htpasswd + Day 6 mint) — Demo 2E and Demo 6
source day-6/demo-users.env
# DEMO_RETAIL_KEY, DEMO_RISK_KEY, DEMO_PLATFORM_KEY
```

> **Key expiry:** Day 3 keys were minted with a short TTL. If Scenario B returns **403** (not 401), run `./day-3/remint-demo-keys.sh` and `source day-3/demo-env.sh` again.

> **Scenario D (Granite 200):** After Day 6 persona isolation, `granite-tiny-gpu-premium` no longer includes Granite. Use **`${DEMO_RISK_KEY}`** or **`${DEMO_PLATFORM_KEY}`** for Scenario D instead of `${ADVANCED_USER_KEY}`.

> **Model IDs:** Use `facebook/opt-125m` for simulator and `granite-4-tiny-gpu` for Granite in the JSON `"model"` field (from `GET .../v1/models`).

> **Multi-user setup:** Three htpasswd personas (`demo-retail-analyst`, `demo-risk-analyst`, `demo-platform-ops`) each mint their own API keys so observability metrics show distinct **user** labels. See [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md) for setup and [day-1/setup-multi-user.sh](day-1/setup-multi-user.sh) for IdP install. For **Gen AI playground** in the RHOAI UI, each persona must also create a dedicated project — [07-ui Step 0.1](07-ui-based-demonstration-steps.md#step-01--create-rhoai-projects-before-playground).

### Pre-flight checklist

- `oc whoami` succeeds; dashboard accessible
- `maas-default-gateway` Programmed
- Granite and simulator pods Running in `llm` namespace
- `payload-pre-processing` Running in `openshift-ingress`
- NeMo Guardrails Ready (`nemo-poc-guardrails` in `redhat-ods-applications`)
- (Advanced) ConfigMaps labeled `maas.opendatahub.io/advanced-guardrails=true` — after Day 4 re-install on this branch
- `demo-users.env` loaded (`source day-6/demo-users.env`) — persona keys minted per-user, not admin
- htpasswd IdP active (`oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}'` includes `maas-demo-users`)
- Persona groups exist (`oc get group maas-demo-retail-analyst maas-demo-risk-analytics maas-demo-platform-ops`)
- Observability — `data-science-perses` Running; see [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md) if dashboard fails
- (Optional) Day 7 Lightspeed — `lightspeed-app-server` Ready; `source day-7/lightspeed-maas.env`
- API keys minted for basic and advanced tiers (Day 3 auth demos) **and** three persona keys (Day 6)
- Daily traffic run at least once (`./day-6/daily-traffic.sh` or `--quick` on demo morning)
- Terminal font size readable for audience
- Backup: [MaaS feature video](https://drive.google.com/file/d/17pLFqDMEi2-XjxsWp70saDPyb_IHHoHf/view) and [gateway flow animation](https://noyitz.github.io/ai-gateway-docs/ai-gateway-flow.html)

### Presenter console tabs (recommended)

1. Terminal — curl commands
2. OpenShift Console — Workloads → `llm` (models) and `models-as-a-service` (subscriptions, groups)
3. Browser — RHOAI dashboard / Observability (Demo 6)
4. Gateway flow animation (Demo 1 talking aid)
5. (Optional) OpenShift login page — show htpasswd provider `maas-demo-users` for persona login demo

---

## Demo 1: Enterprise AI Gateway — Model Routing

**Duration:** 5–7 minutes  
**Objective:** Show gateway-enforced routing to GPU Granite vs CPU simulator through a **single unified endpoint** with body-based model selection.

### Talking points

- Enterprise governed "front door" — applications call one URL and specify the model in the JSON body
- `payload-pre-processing` extracts `"model"` into `X-Gateway-Model-Name` before Kuadrant auth
- Authorino validates API keys; Kuadrant enforces subscriptions and rate limits
- Same gateway hostname, different backends selected by body field
- **Multi-user angle:** Each LOB team uses their own API key; the gateway routes by model in the body while subscriptions enforce which models each team may call (Demo 2E)

> **Cluster note (Day 4):** Unified `${MAAS_URL}/v1/chat/completions` works with API keys. For **401/403 auth demos**, use model-specific paths in Demo 2 (see [day-4/CHANGES.md](day-4/CHANGES.md)).

### Step 1.1 — Show unified endpoint

```bash
echo "Unified:   ${UNIFIED_URL}"
echo "Simulator: ${SIM_URL}/v1/chat/completions  (auth demo fallback)"
echo "Granite:   ${GRAN_URL}/v1/chat/completions  (auth demo fallback)"
```

Open [AI Gateway Flow animation](https://noyitz.github.io/ai-gateway-docs/ai-gateway-flow.html) and walk through: Consumer → Envoy → pre-processing → Authorino → vLLM.

### Step 1.2 — Route to CPU simulator (unified endpoint)

```bash
curl -s -X POST "${UNIFIED_URL}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BASIC_USER_KEY}" \
  -d '{
    "model": "facebook/opt-125m",
    "messages": [{"role": "user", "content": "Hello, which model are you?"}],
    "max_tokens": 30
  }' | jq .
```

**Expected:** HTTP 200, simulator response in `choices[0].message.content`.

### Step 1.3 — Route to Granite (unified endpoint, advanced key)

```bash
curl -s -X POST "${UNIFIED_URL}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ADVANCED_USER_KEY}" \
  -d '{
    "model": "granite-4-tiny-gpu",
    "messages": [{"role": "user", "content": "Summarize MaaS governance in one sentence."}],
    "max_tokens": 50
  }' | jq .
```

**Expected:** HTTP 200, Granite model response.

### Step 1.4 — Multi-user routing (optional, persona keys)

Show that **different teams** hit the same gateway with different keys and models — subscriptions govern access:

**Retail Analyst — simulator only:**

```bash
curl -s -o /dev/null -w "retail → simulator: HTTP %{http_code}\n" \
  -X POST "${SIM_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_RETAIL_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Hello"}],"max_tokens":15}'
```

**Risk Analytics — Granite:**

```bash
curl -s -o /dev/null -w "risk → granite: HTTP %{http_code}\n" \
  -X POST "${GRAN_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_RISK_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"granite-4-tiny-gpu","messages":[{"role":"user","content":"Hello"}],"max_tokens":30}'
```

**Platform Engineering — all models (example: external):**

```bash
curl -s -o /dev/null -w "platform → external: HTTP %{http_code}\n" \
  -X POST "${EXT_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_PLATFORM_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"codellama-7b-instruct","messages":[{"role":"user","content":"Hello"}],"max_tokens":20}'
```

**Talking point:** Same gateway URL space; entitlements differ by subscription tied to OpenShift group membership ([MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md)).

### Step 1.5 — Show backend pods (optional)

```bash
oc get pods -n llm -o wide
```

Point out Granite pods on GPU nodes vs simulator on CPU worker.

### Fallback

If live inference fails, show pre-recorded [MaaS feature video](https://drive.google.com/file/d/17pLFqDMEi2-XjxsWp70saDPyb_IHHoHf/view).

---

## Demo 2: Authentication, Authorization, and RBAC

**Duration:** 10–12 minutes (includes Scenario E multi-user entitlements)  
**Objective:** Prove zero-trust enforcement at the gateway before traffic reaches model servers.

### Talking points

- Authorino validates bearer tokens against PostgreSQL subscription store
- Client credentials stripped before forwarding to vLLM (exfiltration mitigation)
- Group-based entitlements control which models each team can access — three htpasswd personas map to OpenShift groups and MaaSSubscription owner groups

### Scenario A — Unauthorized (401)

```bash
curl -i -X POST "${SIM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "facebook/opt-125m",
    "messages": [{"role": "user", "content": "Ping"}],
    "max_tokens": 5
  }'
```

**Expected:** `HTTP/1.1 401 Unauthorized` — blocked at gateway, never reaches model pod.

**Talking point:** "No API key, no inference — even if the model pod is healthy."

### Scenario B — Authorized basic tier (200)

```bash
curl -i -X POST "${SIM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BASIC_USER_KEY}" \
  -d '{
    "model": "facebook/opt-125m",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 15
  }'
```

**Expected:** `HTTP/1.1 200 OK` with model response body.

### Scenario C — Entitlement violation (403)

```bash
curl -i -X POST "${GRAN_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BASIC_USER_KEY}" \
  -d '{
    "model": "granite-4-tiny-gpu",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 10
  }'
```

**Expected:** `HTTP/1.1 403 Forbidden` — basic subscription does not include Granite.

**Talking point:** "Declarative MaaSSubscription CRs enforce tier boundaries without application code changes."

### Scenario D — Granite authorized (200)

> Uses a persona key with Granite entitlement (`demo-risk-analytics` or `demo-platform-ops`). `${ADVANCED_USER_KEY}` no longer grants Granite after Day 6 restrictions.

```bash
curl -i -X POST "${GRAN_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DEMO_RISK_KEY}" \
  -d '{
    "model": "granite-4-tiny-gpu",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 30
  }'
```

**Expected:** `HTTP/1.1 200 OK`.

### Scenario E — Multi-user group entitlements (persona keys)

Uses keys minted **as each htpasswd user** (not admin). Requires `source day-6/demo-users.env`.

**E.1 — Retail Analyst denied Granite (403):**

```bash
curl -i -X POST "${GRAN_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DEMO_RETAIL_KEY}" \
  -d '{
    "model": "granite-4-tiny-gpu",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 10
  }'
```

**Expected:** `HTTP/1.1 403 Forbidden` — `demo-retail-analyst` is in group `maas-demo-retail-analyst`; subscription excludes Granite.

**E.2 — Risk Analytics authorized for Granite (200):**

```bash
curl -i -X POST "${GRAN_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DEMO_RISK_KEY}" \
  -d '{
    "model": "granite-4-tiny-gpu",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 30
  }'
```

**Expected:** `HTTP/1.1 200 OK`.

**E.3 — Platform Engineering — cross-model access (200 on simulator):**

```bash
curl -i -X POST "${SIM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DEMO_PLATFORM_KEY}" \
  -d '{
    "model": "facebook/opt-125m",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 15
  }'
```

**Expected:** `HTTP/1.1 200 OK` — platform subscription includes all three models.

**Talking point:** "Keys are minted by each user after htpasswd login — observability attributes usage to the real identity, not cluster-admin."

### Optional — Show subscription CRs and groups

```bash
oc get maassubscription demo-retail-analyst demo-risk-analytics demo-platform-ops -n models-as-a-service \
  -o 'custom-columns=NAME:.metadata.name,GROUPS:.spec.owner.groups[*].name'
oc get group maas-demo-retail-analyst maas-demo-risk-analytics maas-demo-platform-ops -o custom-columns=NAME:.metadata.name,USERS:.users
```

### Optional — Persona mints their own key (console demo)

1. Open OpenShift Console → **Logout** → login as `demo-retail-analyst` (provider **maas-demo-users**)
2. Terminal: `oc whoami --show-groups` → shows `maas-demo-retail-analyst`
3. Mint key (requires `maas-viewer-role` binding from Day 6):

```bash
curl -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d '{"name":"presenter-retail-key","expiresIn":"24h","subscription":"demo-retail-analyst"}' | jq .
```

See [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md) for full setup.

---

## Demo 3: Token-Based Rate Limiting

**Duration:** 5 minutes  
**Objective:** Demonstrate TPM limits that protect GPU KV-cache from large prompt bursts.

### Talking points

- Request-based limits count HTTP calls only — one large prompt can exhaust GPU memory
- Token-based limits count input + output tokens (`usage.total_tokens`)
- Limitador enforces at gateway via Kuadrant TokenRateLimitPolicy
- **Multi-user angle:** Persona subscriptions use different TPM ceilings — Risk Analytics has 80k/min on Granite vs Retail 3k/min on simulator (visible in Demo 6 dashboard)

### Step 3.1 — Apply strict TPM limit (if not pre-applied)

Patch basic subscription to 2000 tokens/minute:

```yaml
spec:
  quotas:
    - modelRef: facebook-opt-125m-simulated
      tokenLimit: 100000
      rateLimits:
        - limit: 2000
          window: 1m
          metric: tokens
```

```bash
oc apply -f subscription-basic.yaml   # with TPM patch
```

### Step 3.2 — Trigger rate limit

**First request (may succeed):**

```bash
curl -i -X POST "${SIM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BASIC_USER_KEY}" \
  -d '{
    "model": "facebook/opt-125m",
    "messages": [{
      "role": "user",
      "content": "Please write a long, exhaustive architectural essay containing at least one thousand words discussing the implementation of Kubernetes operators."
    }],
    "max_tokens": 50
  }'
```

**Second request immediately after:**

```bash
curl -i -X POST "${SIM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BASIC_USER_KEY}" \
  -d '{
    "model": "facebook/opt-125m",
    "messages": [{"role": "user", "content": "Another large request to exceed TPM."}],
    "max_tokens": 50
  }'
```

**Expected:** Second request returns `HTTP/1.1 429 Too Many Requests` with Limitador enforcement message.

---

## Demo 4: Multi-Replica EPP Load Balancing (Optional)

**Duration:** 5 minutes  
**Objective:** Show intelligent scheduling across 2 Granite replicas on separate GPU nodes.

### Step 4.1 — Show replica placement

```bash
oc get pods -n llm -l serving.kserve.io/inferenceservice=granite-4-tiny-gpu -o wide
```

**Expected:** 2 pods on different GPU worker hostnames.

### Step 4.2 — Prefix cache locality (optional)

Send repeated requests with identical prefix:

```bash
for i in 1 2 3; do
  curl -s -X POST "${GRAN_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ADVANCED_USER_KEY}" \
    -d '{
      "model": "granite-4-tiny-gpu",
      "messages": [{"role": "user", "content": "The capital of France is"}],
      "max_tokens": 30
    }' | jq -r '.choices[0].message.content' | head -c 80
  echo "..."
done
```

**Talking point:** EPP scheduler uses KV-cache utilization and prefix-cache scoring to route to optimal replica.

> **Known issue:** Ensure container port is explicit in LLMInferenceService spec (see [06-troubleshooting.md](06-troubleshooting.md#prefix-cache-inefficiencies-rhoaieng-58969)).

---

## Demo 5: NeMo Guardrails Content Safety (+ Advanced)

**Duration:** 5 minutes baseline; **+8–10 minutes** for Advanced A/B  
**Objective:** Safety layer blocks forbidden input before it reaches the LLM; advanced track shows **scoped packs** and **pluggable providers**.

> **Deployed Day 4:** `nemo-poc-guardrails` in `redhat-ods-applications`. Uses CPU internal detectors (Presidio + regex). Technology Preview.  
> **Advanced track:** [09-advanced-guardrails-plan.md](09-advanced-guardrails-plan.md) — policy packs + `day-4/demo-advanced-guardrails.sh` (requires Day 6 persona env for scoped story).

### Step 5.1 — Confirm guardrails route

```bash
echo "Guardrails: ${GUARDRAILS_URL}"
oc get nemoguardrails nemo-poc-guardrails -n redhat-ods-applications
oc get configmap -n redhat-ods-applications -l maas.opendatahub.io/advanced-guardrails=true
```

### Step 5.2 — Safe prompt

```bash
curl -sk -X POST "${GUARDRAILS_URL}/v1/guardrail/checks" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -d '{
    "model": "test",
    "messages": [{"role": "user", "content": "What is compound interest?"}]
  }' | jq .
```

**Expected:** `"status": "success"`.

### Step 5.3 — Blocked prompt

```bash
curl -sk -X POST "${GUARDRAILS_URL}/v1/guardrail/checks" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -d '{
    "model": "test",
    "messages": [{"role": "user", "content": "My password is secret123"}]
  }' | jq .
```

**Expected:** `"status": "blocked"` — regex rail matches "password".

---

### Demo 5A — Scoped policies (user / client / role / org) ≈5 min

**Objective:** Same prompt, different outcomes by **organization / role** pack — independent of model entitlement.

**Talking points**

- Subscriptions decide *which models*; guardrail bindings decide *which content policy*
- Packs: `rails-retail` (strict secrets/PII), `rails-risk` (jailbreak + SSN; password allowlisted for ops), `rails-platform` (diagnostics)
- Bindings are PoC ConfigMaps today — target CR shape in the plan doc

```bash
source day-6/demo-users.env
./day-4/demo-advanced-guardrails.sh scoped
```

| Persona / scope | Pack | Prompt | Expected |
|-----------------|------|--------|----------|
| Retail / `org-retail` | `rails-retail` | `My password is secret123` | **blocked** (live NeMo) |
| Risk / `org-risk` | `rails-risk` | Same password prompt | **success** (ops allowlist) |
| Platform / role | `rails-platform` | `How do I run a password reset…` | **success** |
| Risk | `rails-risk` | Jailbreak phrasing | **blocked** |

**Optional client override talking point:** `clientId: mobile-banking` at higher priority than org default — shown in `guardrail-policy-bindings` ConfigMap.

---

### Demo 5B — Pluggable providers ≈5 min

**Objective:** One check contract; swap backends (NeMo live; Azure / AWS mocked unless configured).

**Talking points**

- Defense-in-depth: local NeMo rails + optional enterprise provider ([PANW + NeMo pattern](https://www.paloaltonetworks.com/blog/network-security/securing-genai-with-ai-runtime-security-and-nvidia-nemo-guardrails/))
- Registry: ConfigMap `guardrail-provider-registry` in `redhat-ods-applications`
- Never commit Azure/AWS keys — mocks are default on this branch

```bash
./day-4/demo-advanced-guardrails.sh providers
```

**Expected:** Same password prompt → `provider: nemo|azure|aws` with `status: blocked` and **different** `reasons` shapes.

---

## Demo 7: External Model via MaaS Gateway (Day 5)

**Duration:** 5 minutes  
**Objective:** Show governed routing to an **external** OpenAI-compatible provider (Red Hat workshop LiteLLM) through the same MaaS gateway.

### Talking points

- Platform teams register external providers once via `ExternalModel` CR; users keep using MaaS API keys
- Gateway strips user credentials and injects the provider key from a Kubernetes secret
- Same subscription and quota model as local Granite/simulator models
- Technology Preview in RHOAI 3.4

> **Use the model-specific path** — unified `/v1/chat/completions` does not inject provider credentials for external models on this cluster ([day-5/CHANGES.md](day-5/CHANGES.md)).

### Step 7.1 — Show external model registration

```bash
oc get externalmodel,maasmodelref codellama-7b-instruct -n llm
echo "External endpoint: ${EXT_URL}/v1/chat/completions"
```

### Step 7.2 — Inference with MaaS API key (basic tier)

```bash
curl -s -X POST "${EXT_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${BASIC_USER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "codellama-7b-instruct",
    "messages": [{"role": "user", "content": "Explain MaaS external routing in one sentence."}],
    "max_tokens": 40
  }' | jq .
```

**Expected:** HTTP 200, response from LiteLLM-hosted `codellama-7b-instruct`.

### Step 7.3 — Multi-user external access (persona keys)

Retail and Risk personas both include the external model; Platform has all endpoints:

```bash
curl -s -o /dev/null -w "retail → codellama: HTTP %{http_code}\n" \
  -X POST "${EXT_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_RETAIL_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"codellama-7b-instruct","messages":[{"role":"user","content":"Hello"}],"max_tokens":20}'

curl -s -o /dev/null -w "risk → codellama: HTTP %{http_code}\n" \
  -X POST "${EXT_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_RISK_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"codellama-7b-instruct","messages":[{"role":"user","content":"Hello"}],"max_tokens":20}'
```

**Expected:** Both **200** — external model is in both subscriptions; usage appears under distinct **user** labels in Demo 6.

### Step 7.4 — Contrast with direct provider access (optional talking point)

Applications without MaaS would embed the LiteLLM workshop key directly. With MaaS, only the platform secret holds that key — users never see it.

---

## Demo 6: Observability and Cost Showback (Technology Preview)

**Duration:** 8–10 minutes  
**Objective:** Show token consumption metrics, per-user attribution, and CSV export for financial showback.

> **Requires Day 6:** Full observability stack (COO + RHOAI Perses backend + datasource secret). See [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md) if the dashboard shows **Service Unavailable**. Run `./day-6/daily-traffic.sh` daily; use `--quick` on demo morning.

### Demo users and rate limits

Each persona uses a **dedicated API key minted by that htpasswd user** so the Observability dashboard shows separate user series (not all `admin`).


| Persona              | htpasswd user         | Env variable        | Subscription          | Models              | Token limit (per model) | Cost center        |
| -------------------- | --------------------- | ------------------- | --------------------- | ------------------- | ----------------------- | ------------------ |
| Retail Analyst       | `demo-retail-analyst` | `DEMO_RETAIL_KEY`   | `demo-retail-analyst` | Simulator, external | 3,000 / min             | `CC-RETAIL-1001`   |
| Risk Analytics       | `demo-risk-analyst`   | `DEMO_RISK_KEY`     | `demo-risk-analytics` | Granite, external   | 80,000 / min (Granite)  | `CC-RISK-2001`     |
| Platform Engineering | `demo-platform-ops`   | `DEMO_PLATFORM_KEY` | `demo-platform-ops`   | All three           | 10k–25k / min           | `CC-PLATFORM-3001` |


Load keys before presenting:

```bash
source day-6/demo-users.env
```

### Talking points

- OpenTelemetry + Kuadrant telemetry collect token metrics at the gateway
- `tokenMetadata` on subscriptions drives **cost center** and **organization** labels
- Distinct API keys minted by each htpasswd persona appear as separate **users** in charts (not all `admin` — see [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md))
- Rate limits differ by persona — Risk team has highest Granite quota

### Step 6.1 — Seed traffic (if not run today)

```bash
./day-6/daily-traffic.sh --quick
# or full daily seed:
./day-6/daily-traffic.sh
```

### Step 6.1b — Live per-persona requests (optional, before opening dashboard)

Generate fresh hits attributed to each user:

```bash
source day-6/demo-users.env

curl -s -o /dev/null -w "retail: HTTP %{http_code}\n" \
  -X POST "${MAAS_URL}/llm/facebook-opt-125m-simulated/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_RETAIL_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Retail demo"}],"max_tokens":20}'

curl -s -o /dev/null -w "risk: HTTP %{http_code}\n" \
  -X POST "${MAAS_URL}/llm/granite-4-tiny-gpu/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_RISK_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"granite-4-tiny-gpu","messages":[{"role":"user","content":"Risk demo"}],"max_tokens":30}'

curl -s -o /dev/null -w "platform: HTTP %{http_code}\n" \
  -X POST "${MAAS_URL}/llm/codellama-7b-instruct/v1/chat/completions" \
  -H "Authorization: Bearer ${DEMO_PLATFORM_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"codellama-7b-instruct","messages":[{"role":"user","content":"Platform demo"}],"max_tokens":25}'
```

**Expected:** Three **200** responses — each increments metrics for `demo-retail-analyst`, `demo-risk-analyst`, and `demo-platform-ops`.

### Step 6.2 — Open Observability dashboard

1. RHOAI Console → **Observe & monitor** → **Dashboard (Tech Preview)**
2. Open **MaaS usage** (`dashboard-3-maas-usage-admin`)
3. Group/filter by **user**, **subscription**, **cost_center**, or **model**

**Fallback (OpenShift Console):** Administrator → **Observe → Metrics**:

```promql
count by (user, subscription) (authorized_hits{subscription=~"demo-.*", user=~"demo-.*"})
```

Filter excludes legacy `admin`-minted series. See [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md) and [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md).

### Step 6.3 — Highlight per-user differences

Point out three distinct **user** series (not a single `admin` line):

- **Risk Analytics** (`demo-risk-analyst`) — highest TPM (Granite-heavy requests), cost center `CC-RISK-2001`
- **Retail Analyst** (`demo-retail-analyst`) — low flat usage (simulator + external), `CC-RETAIL-1001`
- **Platform Engineering** (`demo-platform-ops`) — multi-model spread, `CC-PLATFORM-3001`

**Talking point:** Keys minted by cluster-admin would collapse all usage under `user=admin`; per-user minting ([day-6/mint-persona-keys.sh](day-6/mint-persona-keys.sh)) enables LOB showback.

### Step 6.4 — Export showback CSV

Click **Export CSV** in the dashboard for mock chargeback reporting.

### Daily traffic schedule (pre-demo)


| When         | Command                            |
| ------------ | ---------------------------------- |
| Day 6+ daily | `./day-6/daily-traffic.sh`         |
| Demo morning | `./day-6/daily-traffic.sh --quick` |


See [day-6/README.md](day-6/README.md) for cron setup and [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md) for dashboard recovery.

> **Note:** Observability dashboard is **Technology Preview** in RHOAI 3.4.

---

## Drink your own champagne — OpenShift Lightspeed on MaaS (Optional, Day 7)

**Duration:** 3–5 minutes  
**Placement:** Closing optional segment — *“We run our own AI assistant on the same governed gateway.”*  
**Not on core slide track** (Slides 3–6).

### Prerequisites

- Day 7 complete — [day-7/README.md](day-7/README.md)
- Presenter logged in as **cluster-admin**
- `lightspeed-app-server` Ready in `openshift-lightspeed`
- Granite pod Ready with vLLM tool-calling flags (`--enable-auto-tool-choice`, `--tool-call-parser=granite`) — applied by [day-7/run-day7-install.sh](day-7/run-day7-install.sh)

### Governance context


| Item                | Value                                                      |
| ------------------- | ---------------------------------------------------------- |
| Lightspeed provider | `maas-gateway` (`type: openai`)                            |
| MaaS URL            | `${MAAS_URL}/v1`                                           |
| Model               | `qwen3-4b-instruct`                                        |
| Subscription        | `demo-openshift-lightspeed`                                |
| Rate limit          | 50,000 tokens / min                                        |
| Cost center         | `CC-LIGHTSPEED-4001`                                       |
| Credential          | `openshift-lightspeed/maas-gateway-api-key` (MaaS API key) |


### Step OLS.1 — Show configuration (optional, terminal)

```bash
oc get olsconfig cluster -o jsonpath='provider={.spec.ols.defaultProvider} model={.spec.ols.defaultModel} url={.spec.llm.providers[0].url}{"\n"}'
oc get maassubscription demo-openshift-lightspeed -n models-as-a-service -o jsonpath='costCenter={.spec.tokenMetadata.costCenter} tpm={.spec.modelRefs[0].tokenRateLimits[0].limit}{"\n"}'
```

### Step OLS.2 — Open Lightspeed in the console

1. Open **OpenShift Console** (Administrator perspective)
2. Click the **OpenShift Lightspeed** icon in the header
3. Ask a cluster-aware question, for example:
  - *“How many GPU-enabled nodes does this cluster have?”*
  - *“Which namespace hosts the qwen3-4b-instruct model?”*

**Expected:** Lightspeed responds using **Qwen3-4B via the MaaS gateway** (same stack as Demo 1).

### Step OLS.3 — Tie back to observability (optional)

If Demo 6 was shown: Lightspeed’s MaaS key usage appears in Observability metrics under subscription `demo-openshift-lightspeed` / cost center `CC-LIGHTSPEED-4001`.

### Talking points

- Platform teams can standardize **all** LLM consumption — apps *and* operator UX — on one gateway
- No shadow OpenAI keys in Lightspeed; credentials live in a Kubernetes secret tied to a **MaaSSubscription**
- **Qwen3-4B** chosen for Lightspeed: pre-configured Hermes tool calling + better cluster Q&A than Granite tiny
- “Drink your own champagne” — the platform consumes its own governed MaaS gateway

### Fallback

If Lightspeed UI is unavailable, show the direct probe:

```bash
source day-7/lightspeed-maas.env

# Plain chat (must be HTTP 200)
curl -s -o /dev/null -w "plain: HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${LIGHTSPEED_MAAS_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-4b-instruct","messages":[{"role":"user","content":"Summarize MaaS in one sentence."}],"max_tokens":40}'

# Tool calling — same path Lightspeed uses (must be HTTP 200, not 400)
curl -s -o /dev/null -w "tool_choice auto: HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${LIGHTSPEED_MAAS_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-4b-instruct","messages":[{"role":"user","content":"ping"}],"max_tokens":10,"tool_choice":"auto","tools":[{"type":"function","function":{"name":"noop","description":"No-op","parameters":{"type":"object","properties":{}}}}]}'
```

If `tool_choice auto` returns **400**, verify Qwen vLLM tool-calling flags and MaaS registration — see [06-troubleshooting.md](06-troubleshooting.md) and re-run [day-7/run-day7-install.sh](day-7/run-day7-install.sh).

---

## Demo Timing Summary


| Demo | Topic                               | Duration  | Required         |
| ---- | ----------------------------------- | --------- | ---------------- |
| 1    | Body-based routing                  | 5–7 min   | Yes              |
| 2    | AuthN / AuthZ / RBAC (+ multi-user) | 10–12 min | Yes              |
| 3    | Token rate limiting                 | 5 min     | Yes              |
| 4    | EPP load balancing                  | 5 min     | Optional         |
| 5    | NeMo Guardrails (+ Advanced A/B)    | 5–15 min  | Yes (Day 4; A/B needs Day 6) |
| 6    | Observability showback              | 8–10 min  | Yes (Day 6)      |
| 7    | External LiteLLM model              | 5 min     | Yes (Day 5)      |
| OLS  | Lightspeed on MaaS (“champagne”)    | 3–5 min   | Optional (Day 7) |


---

## Presentation Slide Mapping


| Slide                          | Demo coverage                                                                    |
| ------------------------------ | -------------------------------------------------------------------------------- |
| Slide 3 — Architecture         | Demo 1 (gateway flow), Demo 7 (external routing)                                 |
| Slide 4 — Deterministic proofs | Demo 2 (401/403, **2E multi-user entitlements**), Demo 3 (429), Demo 5 (blocked + **5A/5B**) |
| Slide 5 — Fleet economics      | Demo 4 (EPP replicas)                                                            |
| Slide 6 — Observability        | Demo 6 (three htpasswd users, per-user TPM, cost center CSV)                     |


---

## Related Documents

- [04-installation-and-ready-state.md](04-installation-and-ready-state.md) — prerequisites
- [09-advanced-guardrails-plan.md](09-advanced-guardrails-plan.md) — scoped packs + pluggable providers
- [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md) — htpasswd IdP, groups, per-user API keys
- [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md) — RHOAI UI presenter script (client demos)
- [06-troubleshooting.md](06-troubleshooting.md) — live demo recovery
- [day-6/README.md](day-6/README.md) — COO + daily traffic
- [day-7/README.md](day-7/README.md) — OpenShift Lightspeed (optional)
- [01-engineering-blueprint.md](01-engineering-blueprint.md) — architecture reference

