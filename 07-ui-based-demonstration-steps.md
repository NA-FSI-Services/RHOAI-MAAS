# UI-Based Live Demonstration Steps

Presenter runbook for demonstrating the RHOAI 3.4 MaaS PoC **primarily through the RHOAI AI Console**, with terminal fallbacks where the UI cannot show a behavior.

Execute **after** [04-installation-and-ready-state.md](04-installation-and-ready-state.md). For curl-first demos, see [05-demonstration-steps.md](05-demonstration-steps.md).

**Total estimated time:** 45–55 minutes (core UI demos); 65–75 minutes with optional segments.

---

## Console URLs

Set `CLUSTER_DOMAIN` first (see [05-demonstration-steps.md](05-demonstration-steps.md#pre-demo-setup)):

```bash
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
```

| Console | URL (derive from your cluster) |
|---------|-------------------------------|
| **RHOAI AI Console** | `https://rh-ai.${CLUSTER_DOMAIN}` |
| **OpenShift Console** | `https://console-openshift-console.${CLUSTER_DOMAIN}` |
| **MaaS gateway** (shown in UI, not browsed directly) | `https://maas.${CLUSTER_DOMAIN}` |

---

## Pre-Demo Setup

### Browser tabs (recommended)

1. **RHOAI AI Console** — logged in as **cluster admin** (primary presenter tab)
2. **RHOAI AI Console** (private/incognito) — for persona login (`demo-retail-analyst`, etc.)
3. **OpenShift Console** — Administrator perspective (GPU pods, optional Lightspeed)
4. **Backup:** [AI Gateway flow animation](https://noyitz.github.io/ai-gateway-docs/ai-gateway-flow.html)

### Pre-flight checklist

- [ ] RHOAI dashboard loads; left nav shows **Gen AI studio** and **Observe & monitor**
- [ ] **Settings → Subscriptions** lists demo personas (`demo-retail-analyst`, `demo-risk-analytics`, `demo-platform-ops`) as **Active**
- [ ] **Settings → Authorization policies** lists matching demo policies
- [ ] **Observe & monitor → Dashboard** loads (not “Service Unavailable”) — see [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md)
- [ ] `./day-6/daily-traffic.sh` run at least once (or `--quick` on demo morning)
- [ ] htpasswd IdP **`maas-demo-users`** available on OpenShift login page — see [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md)
- [ ] Each persona has a **dedicated RHOAI project** for playground (e.g. `maas-demo-retail`) — see [Step 0.1](#step-01--create-rhoai-projects-before-playground)
- [ ] Terminal prepared **only** for Demo 2 (401/403/429) and Demo 5 fallbacks — keep minimized until needed

### Screenshot folder

Capture screenshots during rehearsal and save under `screenshots/07-ui/`. Placeholders below use that path.

---

## Step 0.1 — Create RHOAI projects (before playground)

**When:** Before Demo 1 Step 1.4, Demo 2 Part B playground steps, or Demo 7 Step 7.2 — for **persona users** (and optionally admin).

Gen AI Studio playground writes **ConfigMaps** into the **project namespace** selected in the RHOAI UI. You must use a project where you can **create assets** — typically a project **you created**, not a shared read-only namespace (e.g. `grafana`).

### Persona project names (suggested)

| Persona | htpasswd user | Create project |
|---------|---------------|----------------|
| Retail Analyst | `demo-retail-analyst` | `maas-demo-retail` |
| Risk Analytics | `demo-risk-analyst` | `maas-demo-risk` |
| Platform Ops | `demo-platform-ops` | `maas-demo-platform` |

Presenter (admin) may use any owned project, e.g. `maas-demo-admin`.

### Create project (RHOAI UI)

1. Log in to the **RHOAI AI Console** as the persona (or admin).
2. Open the **project** drop-down in the top navigation bar.
3. Click **Create project**.
4. **Project name:** e.g. `maas-demo-retail` (valid DNS subdomain; lowercase, no spaces).
5. Click **Create** — you become **admin** of the new namespace and can create playground ConfigMaps.
6. Confirm the new project is **selected** in the drop-down before opening the playground.

> **Screenshot:** Create project dialog with name `maas-demo-retail`.  
> ![Create RHOAI project](screenshots/07-ui/00-create-project.png)

**Talking point:** “Each LOB team owns a project namespace; playground state stays isolated per team.”

### Alternative (OpenShift Console)

**Home → Projects → Create Project** — same namespace name, while logged in as the persona.

### If you see `configmaps is forbidden`

You are on a project without create permission. Switch to your dedicated project or create one — see [06-troubleshooting.md](06-troubleshooting.md#gen-ai-playground--configmap-forbidden-wrong-project).

---

## Demo 1: Enterprise AI Gateway — Model Discovery & Playground

**Duration:** 7–10 minutes  
**Objective:** Show the governed model catalog, MaaS badges, endpoint URLs, and interactive inference through Gen AI Studio — the same gateway applications call programmatically.

**Primary UI path:** RHOAI → **Gen AI studio** → **AI asset endpoints**

### Talking points

- Platform teams publish models once; LOB teams discover endpoints and quotas in a single UI
- Every MaaS model shows gateway URL, subscription selector, and API key tools
- Playground traffic flows through the same Kuadrant gateway as production API calls

### Step 1.1 — Open the model catalog

1. Log in to the **RHOAI AI Console** as cluster admin.
2. In the left navigation, click **Gen AI studio** → **AI asset endpoints**.
3. Confirm the **Models** tab lists deployed models including:
   - `facebook-opt-125m-simulated` (simulator)
   - `granite-4-tiny-gpu` (Granite)
   - `codellama-7b-instruct` (external / LiteLLM)

> **Screenshot:** Model catalog with Status **Ready** and **View** in the Endpoints column.  
> ![AI asset endpoints — model catalog](screenshots/07-ui/01-model-catalog.png)

### Step 1.2 — Show MaaS endpoint details (simulator)

1. On the **Models** tab, locate **facebook-opt-125m-simulated**.
2. Click **View** in the **Endpoints** column.
3. In the **Endpoints** dialog, point out:
   - **Model as a Service** badge at the top
   - **External API endpoint URL** (gateway path under `maas.apps...`)
   - **Subscription** dropdown (admin may see multiple subscriptions)
   - **Generate API key** (1-hour temporary key for quick tests)

> **Screenshot:** Endpoints dialog for the simulator with MaaS badge and gateway URL.  
> ![MaaS endpoints dialog — simulator](screenshots/07-ui/02-endpoints-simulator.png)

**Talking point:** “Applications copy this URL; the gateway routes to the correct backend — no direct pod access.”

### Step 1.3 — Show Granite and external model endpoints

Repeat Step 1.2 for:

| Model | Highlight |
|-------|-----------|
| **granite-4-tiny-gpu** | GPU-hosted local model |
| **codellama-7b-instruct** | External provider (LiteLLM) through the **same** gateway |

> **Screenshot:** Endpoints dialog for CodeLlama showing external model registration.  
> ![MaaS endpoints dialog — external CodeLlama](screenshots/07-ui/03-endpoints-external-codellama.png)

### Step 1.4 — Interactive inference in the playground

> **Prerequisite:** Complete [Step 0.1](#step-01--create-rhoai-projects-before-playground) — select your **own** project (e.g. `maas-demo-admin` as admin, `maas-demo-retail` as retail persona). Do **not** use shared read-only projects such as `grafana`.

1. Confirm the correct **project** is selected in the top navigation bar.
2. On **AI asset endpoints → Models**, locate **granite-4-tiny-gpu** (admin) or **facebook-opt-125m-simulated** (retail persona).
3. Click the row **Actions** menu (⋮) → **Try in playground** (or **Add to playground** → configure if first use in this project).
4. In the playground tab:
   - Select subscription **granite-tiny-gpu-premium** or **demo-platform-ops** if prompted
   - Enter prompt: *“Summarize MaaS governance in one sentence.”*
   - Send and show the streaming response

Repeat briefly with the **simulator** model to contrast CPU vs GPU model.

> **Screenshot:** Gen AI Studio playground with Granite response.  
> ![Playground — Granite inference](screenshots/07-ui/04-playground-granite.png)

### Step 1.5 — Models as a service tab (admin view)

1. On **AI asset endpoints**, click the **Models as a service** tab.
2. Review the table columns: model name, endpoint, subscriptions, status.
3. Click **Tier information** (if shown) to explain group → subscription mapping.

> **Screenshot:** Models as a service admin table.  
> ![Models as a service tab](screenshots/07-ui/05-maas-tab.png)

### Optional — Gateway architecture (non-UI)

Open the [AI Gateway Flow animation](https://noyitz.github.io/ai-gateway-docs/ai-gateway-flow.html) if the client asks how routing works under the hood.

### Cannot demonstrate fully in UI

| Behavior | Why | Fallback |
|----------|-----|----------|
| Body-based unified `/v1/chat/completions` routing | Playground uses per-model endpoints, not the unified BBR URL | [05 Demo 1](05-demonstration-steps.md#demo-1-enterprise-ai-gateway--model-routing) curl to `${MAAS_URL}/v1/chat/completions` |
| Envoy `payload-pre-processing` / header injection | Infrastructure detail, not in RHOAI UI | OpenShift Console → **Workloads → Pods** in `openshift-ingress`, or architecture slide |

---

## Demo 2: Authentication, Authorization, and Multi-User Access

**Duration:** 12–15 minutes  
**Objective:** Show subscription and authorization policy governance in the UI; prove 401/403 enforcement and persona-scoped access.

### Part A — Admin governance (UI)

**Path:** RHOAI → **Settings**

#### Step 2.A.1 — Subscriptions

1. Click **Settings** → **Subscriptions**.
2. Filter or scroll to demo subscriptions:

| Subscription | Groups | Models | Priority |
|--------------|--------|--------|----------|
| `demo-retail-analyst` | `maas-demo-retail-analyst` | Simulator, CodeLlama | 11 |
| `demo-risk-analytics` | `maas-demo-risk-analytics` | Granite, CodeLlama | 21 |
| `demo-platform-ops` | `maas-demo-platform-ops` | All three | 15 |

3. Click **demo-retail-analyst** → **View details**.
4. Show **token rate limits** and **token metadata** (cost center `CC-RETAIL-1001`, org `org-retail`).

> **Screenshot:** Subscription details — retail persona.  
> ![Subscription details — demo-retail-analyst](screenshots/07-ui/06-subscription-retail.png)

**Talking point:** “Quota and showback metadata are declarative — no application code changes.”

#### Step 2.A.2 — Authorization policies

1. Click **Settings** → **Authorization policies**.
2. Open **demo-retail-analyst-access**, **demo-risk-analytics-access**, **demo-platform-ops-access**.
3. Compare **Groups** and **Models** — retail excludes Granite; risk includes Granite; platform includes all three.

> **Screenshot:** Authorization policies list.  
> ![Authorization policies table](screenshots/07-ui/07-auth-policies.png)

#### Step 2.A.3 — API keys (admin view)

1. Click **Gen AI studio** → **API keys**.
2. Show keys filtered by user (`demo-retail-analyst`, `demo-risk-analyst`, `demo-platform-ops`).
3. Point out **Status**, **Subscription**, **Created**, **Last used** columns.

> **Screenshot:** API keys table with persona users.  
> ![API keys — multi-user](screenshots/07-ui/08-api-keys-personas.png)

### Part B — Persona self-service (UI)

> **Prerequisite:** Persona has completed [Step 0.1](#step-01--create-rhoai-projects-before-playground) and selected their project (e.g. `maas-demo-retail`).

1. Open a **private browser window**.
2. Log in to **OpenShift** with user **`demo-retail-analyst`** (IdP: **maas-demo-users**).
3. Open the **RHOAI AI Console** (same SSO session).
4. Select project **`maas-demo-retail`** (or create it via **Create project** if first run).
5. Navigate **Gen AI studio** → **AI asset endpoints** → **View** on Granite.

**Expected in UI:** Retail user cannot obtain a working Granite endpoint / subscription for Granite (policy or subscription mismatch — may show Granite in catalog but inference or key creation for Granite subscription fails).

6. **View** simulator or CodeLlama → generate a temporary API key → confirm success.
7. **Try in playground** on simulator (project must be `maas-demo-retail`).

> **Screenshot:** Retail user endpoints — simulator allowed.  
> ![Persona login — retail endpoints](screenshots/07-ui/09-persona-retail-endpoints.png)

8. Repeat login as **`demo-risk-analyst`** — create/select project **`maas-demo-risk`**, show Granite playground or endpoint access.

> **Screenshot:** Risk user playground on Granite.  
> ![Persona login — risk Granite access](screenshots/07-ui/10-persona-risk-granite.png)

**Talking point:** “Keys minted by each user appear as distinct identities in observability — not cluster-admin.”

### Part C — Deterministic auth proofs (terminal required)

The UI always authenticates playground and key flows; you **cannot** trigger **401 Unauthorized** or **403 Forbidden** from the RHOAI dashboard alone.

**Minimize terminal** — run only these three curls (see [05 Demo 2](05-demonstration-steps.md#demo-2-authentication-authorization-and-rbac)):

| Scenario | Expected | Command source |
|----------|----------|----------------|
| **401** — no API key | `HTTP/1.1 401` | Scenario A in doc 05 |
| **403** — basic key on Granite | `HTTP/1.1 403` | Scenario C in doc 05 |
| **403** — retail key on Granite | `HTTP/1.1 403` | Scenario E.1 in doc 05 (`DEMO_RETAIL_KEY`) |

```bash
source day-3/demo-env.sh
source day-6/demo-users.env
# Paste the three curl -i commands from 05-demonstration-steps.md Demo 2
```

> **Screenshot (optional):** Terminal output showing 401 and 403 status lines.  
> ![Terminal — 401 and 403 proofs](screenshots/07-ui/11-terminal-auth-proofs.png)

---

## Demo 3: Token-Based Rate Limiting

**Duration:** 3–5 minutes (UI) + 2 minutes (terminal)  
**Objective:** Explain TPM limits via subscription UI; prove 429 enforcement live.

### Step 3.1 — Show limits in UI (Settings → Subscriptions)

1. **Settings** → **Subscriptions** → **demo-retail-analyst** → **View details**.
2. Highlight per-model token rate limits (e.g. **3,000 tokens/min** on simulator).
3. Open **demo-risk-analytics** → show **80,000 tokens/min** on Granite.

> **Screenshot:** Side-by-side or sequential subscription token limits.  
> ![Subscription token rate limits](screenshots/07-ui/12-subscription-tpm-limits.png)

**Talking point:** “Risk LOB gets a higher Granite ceiling than Retail — visible to admins before any code deploys.”

### Step 3.2 — Playground consumption (optional UI)

In playground, send a large prompt as a retail persona and note token usage indicator (if shown). This illustrates consumption but may **not** trigger 429 in a single click.

### Cannot demonstrate reliably in UI

| Behavior | Why | Fallback |
|----------|-----|----------|
| **429 Too Many Requests** | Requires rapid repeated large prompts exceeding TPM | [05 Demo 3](05-demonstration-steps.md#demo-3-token-based-rate-limiting) — two rapid `curl` calls with `BASIC_USER_KEY` |

---

## Demo 4: Multi-Replica EPP Load Balancing (Optional)

**Duration:** 5 minutes  
**Objective:** Show Granite replicas on separate GPU nodes.

### UI path: OpenShift Console (not RHOAI)

1. Open **OpenShift Console** → **Administrator** perspective.
2. **Workloads** → **Pods** → namespace **`llm`**.
3. Filter by `granite-4-tiny-gpu`.
4. Show **2 Running pods** on **different worker nodes** (GPU workers).

> **Screenshot:** Granite pods on two GPU nodes.  
> ![OpenShift — Granite replica placement](screenshots/07-ui/13-granite-replicas-nodes.png)

### Cannot demonstrate in RHOAI UI

EPP scheduler decisions and KV-cache routing are not visualized in RHOAI 3.4. Use talking points from [05 Demo 4](05-demonstration-steps.md#demo-4-multi-replica-epp-load-balancing-optional) or optional curl loop in terminal.

---

## Demo 5: NeMo Guardrails Content Safety

**Duration:** 5 minutes  
**Objective:** Show content safety blocking forbidden input before LLM inference.

### Cannot demonstrate in RHOAI UI (this PoC)

NeMo Guardrails is deployed as `nemo-poc-guardrails` in `redhat-ods-applications` but is **not integrated into the RHOAI Gen AI Studio playground** for this PoC. There is no Guardrails tab to click in the client demo.

### UI-adjacent option (OpenShift Console)

1. OpenShift Console → **Operators** → **Installed Operators** → namespace **`redhat-ods-applications`**.
2. Locate **Nemo Guardrails** operator / **`NemoGuardrails`** instance **`nemo-poc-guardrails`** → **Ready**.

> **Screenshot:** NemoGuardrails CR status Ready.  
> ![OpenShift — NemoGuardrails Ready](screenshots/07-ui/14-nemo-guardrails-cr.png)

### Terminal fallback (live proof)

Run safe vs blocked checks from [05 Demo 5](05-demonstration-steps.md#demo-5-nemo-guardrails-content-safety):

```bash
export GUARDRAILS_URL="https://$(oc get route nemo-poc-guardrails -n redhat-ods-applications -o jsonpath='{.spec.host}')"

# Safe → "status": "success"
# Blocked (password) → "status": "blocked"
```

> **Screenshot:** Terminal JSON showing blocked status.  
> ![Terminal — guardrails blocked response](screenshots/07-ui/15-guardrails-blocked-json.png)

---

## Demo 6: Observability and Cost Showback

**Duration:** 10–12 minutes  
**Objective:** Show per-user, per-subscription, per-model usage and CSV export — primary **UI-native** demo for finance stakeholders.

**Path:** RHOAI → **Observe & monitor** → **Dashboard (Tech Preview)**

### Pre-step — Seed traffic (terminal, before client joins)

```bash
./day-6/daily-traffic.sh --quick
```

### Step 6.1 — Open the MaaS usage dashboard

1. In RHOAI, click **Observe & monitor** → **Dashboard**.
2. Open **MaaS usage** (`dashboard-3-maas-usage-admin`).
3. If the page shows **Service Unavailable**, follow [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md) — do not proceed live without a fix.

> **Screenshot:** MaaS usage dashboard landing page.  
> ![Observability — MaaS usage dashboard](screenshots/07-ui/16-maas-usage-dashboard.png)

### Step 6.2 — Filter by user (multi-user showback)

1. Set **Time period** to **Last 24 hours** (or **Last 7 days** if daily traffic has run).
2. In the **User** filter, select **`demo-retail-analyst`**, then **`demo-risk-analyst`**, then **`demo-platform-ops`**.
3. Confirm **three distinct users** — not a single `admin` line (filter out `admin` if legacy series appear).

> **Screenshot:** Dashboard filtered by demo-retail-analyst.  
> ![Dashboard — user filter retail](screenshots/07-ui/17-dashboard-user-retail.png)

> **Screenshot:** Dashboard filtered by demo-risk-analyst (higher Granite volume).  
> ![Dashboard — user filter risk](screenshots/07-ui/18-dashboard-user-risk.png)

**Talking point:** “Each LOB team minted their own API keys — usage attributes to the real htpasswd identity.”

### Step 6.3 — Filter by subscription and cost center

1. **Subscription** filter → `demo-risk-analytics` — show Granite-heavy profile.
2. **Cost center** / metadata → `CC-RISK-2001`, `CC-RETAIL-1001`, `CC-PLATFORM-3001`.
3. **Model** filter → `codellama-7b-instruct` — confirm **external model** usage appears alongside hosted models.

> **Screenshot:** Dashboard filtered by model codellama-7b-instruct.  
> ![Dashboard — external model series](screenshots/07-ui/19-dashboard-external-model.png)

### Step 6.4 — Export showback CSV

1. Click **Export CSV** (or **Export as CSV** per dashboard version).
2. Open the file briefly — show columns for user, subscription, tokens/requests, cost metadata.

> **Screenshot:** CSV export dialog or downloaded file preview.  
> ![CSV export — showback](screenshots/07-ui/20-csv-export.png)

### Fallback — OpenShift Metrics (if Perses fails)

OpenShift Console → **Observe → Metrics**:

```promql
count by (user, subscription, model) (authorized_hits{subscription=~"demo-.*", user=~"demo-.*"})
```

> **Screenshot:** OpenShift Metrics graph with three users.  
> ![OpenShift Metrics — PromQL fallback](screenshots/07-ui/21-openshift-metrics-fallback.png)

---

## Demo 7: External Model via MaaS Gateway

**Duration:** 5–7 minutes  
**Objective:** Show that an external LiteLLM-hosted model is governed like local models — same UI, same API keys, same observability.

**Primary UI path:** RHOAI → **Gen AI studio** → **AI asset endpoints**

### Step 7.1 — External model in catalog

1. **Models** tab → locate **codellama-7b-instruct**.
2. Confirm **Ready** status and **Model as a Service** badge in **View** dialog.
3. Show gateway URL: `.../llm/codellama-7b-instruct/v1/chat/completions`.

> **Screenshot:** External model in catalog (reuse or update screenshot 03).  
> ![External model — catalog row](screenshots/07-ui/22-external-model-catalog.png)

**Talking point:** “Platform registers `ExternalModel` once; users never see the LiteLLM provider key.”

### Step 7.2 — Playground inference (external)

> **Prerequisite:** Select a project where you can create assets ([Step 0.1](#step-01--create-rhoai-projects-before-playground)).

1. Confirm project (e.g. `maas-demo-retail` or `maas-demo-admin`) is selected in the top bar.
2. **Actions (⋮)** → **Try in playground** on **codellama-7b-instruct**.
3. Select subscription **demo-retail-analyst** or **demo-platform-ops**.
4. Prompt: *“Explain external MaaS routing in one sentence.”*
5. Show response from remote CodeLlama via gateway.

> **Screenshot:** Playground response from external model.  
> ![Playground — external CodeLlama](screenshots/07-ui/23-playground-external.png)

### Step 7.3 — Tie to observability

Return to **Demo 6** dashboard → **Model** filter **`codellama-7b-instruct`** → show hits attributed to retail/risk/platform users.

### Cannot demonstrate fully in UI

| Behavior | Fallback |
|----------|----------|
| Provider key injection (two-tier auth) | Talking point + [05 Demo 7.4](05-demonstration-steps.md#step-74--contrast-with-direct-provider-access-optional-talking-point) |
| Unified `/v1/chat/completions` for external | External models require model-specific path on this cluster — [day-5/CHANGES.md](day-5/CHANGES.md) |

---

## Optional: OpenShift Lightspeed on MaaS (Day 7)

**Duration:** 3–5 minutes  
**UI path:** **OpenShift Console** (not RHOAI)

1. Open **OpenShift Console** as cluster admin.
2. Click **OpenShift Lightspeed** icon in the header.
3. Ask: *“How many GPU-enabled nodes does this cluster have?”*
4. Tie back to **Demo 6** — subscription `demo-openshift-lightspeed`, cost center `CC-LIGHTSPEED-4001`.

> **Screenshot:** Lightspeed chat answering a cluster question via MaaS Qwen.  
> ![OpenShift Lightspeed — MaaS-backed response](screenshots/07-ui/24-lightspeed-maas.png)

If Lightspeed UI is unavailable, use terminal fallback in [05 — OLS](05-demonstration-steps.md#drink-your-own-champagne--openshift-lightspeed-on-maas-optional-day-7).

---

## Demo Timing Summary

| Step / Demo | Topic | UI coverage | Duration | Terminal needed? |
|-------------|-------|-------------|----------|------------------|
| **0.1** | **Create RHOAI projects** | **Full UI** | 2–3 min (once per persona) | No |
| 1 | Gateway & playground | **Full UI** | 7–10 min | Optional (BBR URL) |
| 2 | AuthN / AuthZ / multi-user | **Mostly UI** | 12–15 min | **Yes** (401/403) |
| 3 | Token rate limits | **Partial UI** | 5–7 min | **Yes** (429) |
| 4 | EPP replicas | OpenShift UI only | 5 min | Optional |
| 5 | NeMo Guardrails | OpenShift status only | 5 min | **Yes** (live block) |
| 6 | Observability showback | **Full UI** | 10–12 min | Pre-demo traffic only |
| 7 | External model | **Full UI** | 5–7 min | Optional |
| OLS | Lightspeed on MaaS | OpenShift UI | 3–5 min | Fallback if UI down |

---

## Presentation Slide Mapping (UI-first)

| Slide | UI demo coverage |
|-------|------------------|
| Slide 3 — Architecture | Demo 1 (catalog + endpoints), Demo 7 (external in same catalog) |
| Slide 4 — Deterministic proofs | Demo 2 Part C terminal (401/403); Demo 5 terminal (blocked) |
| Slide 5 — Fleet economics | Demo 4 (OpenShift pod placement) |
| Slide 6 — Observability | Demo 6 (dashboard + CSV) — **strongest UI story** |

---

## UI vs Terminal Quick Reference

| Capability | RHOAI UI | OpenShift UI | Terminal |
|------------|----------|--------------|----------|
| Model catalog & MaaS badges | Yes | — | — |
| Playground inference | Yes | — | curl |
| Subscriptions & TPM limits | Yes (admin) | CR YAML | oc get |
| Authorization policies | Yes (admin) | CR YAML | oc get |
| API key self-service | Yes | — | maas-api curl |
| Multi-user persona login | Yes (htpasswd) | Groups | oc login |
| 401 / 403 proofs | No | No | **curl -i** |
| 429 rate limit proof | Unreliable | No | **curl -i** |
| NeMo Guardrails live block | No | CR status only | **curl** |
| MaaS usage dashboard | Yes | Metrics fallback | PromQL |
| External model metrics | Yes (Demo 6 filter) | — | PromQL |
| EPP / GPU placement | No | Yes (pods) | oc get pods |
| Unified BBR endpoint | No | No | curl |
| Lightspeed on MaaS | No | Yes | curl fallback |

---

## Related Documents

- [05-demonstration-steps.md](05-demonstration-steps.md) — curl-first presenter script (terminal proofs)
- [04-installation-and-ready-state.md](04-installation-and-ready-state.md) — prerequisites
- [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md) — htpasswd personas and per-user keys
- [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md) — dashboard recovery
- [06-troubleshooting.md](06-troubleshooting.md) — live demo recovery
- [Red Hat docs — Use MaaS in the dashboard](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/govern_llm_access_with_models-as-a-service/use-models-as-a-service_maas-deploy)
