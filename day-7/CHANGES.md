# Day 7 Installation — Change Log and Deviations

**Date:** 2026-06-05 (updated 2026-07-28 for local Llama)  
**Script:** [run-day7-install.sh](run-day7-install.sh)

---

## 1. Not in original PoC blueprint

| Original plan | Day 7 resolution |
|---------------|------------------|
| MaaS demo ends at gateway + observability | Optional **OpenShift Lightspeed** consumes the same MaaS gateway |
| External LLM for Lightspeed (OpenAI/watsonx) | **Local Llama 3.1 8B on MaaS** — “drink your own champagne” |

---

## 2. Model choice: local Llama 3.1 8B (this cluster)

| Approach | Why |
|----------|-----|
| **llama-3-1-8b-instruct** | Local GPU model already Ready; patched with `--enable-auto-tool-choice` + `--tool-call-parser=llama3_json` |
| Qwen3-4B (earlier sandboxes) | Not deployed on this cluster |
| Granite tiny | Weak quality for Lightspeed Q&A |

**Note:** Plain chat and `tool_choice: auto` through MaaS return **HTTP 200**. Lightspeed needs **`--max-model-len≥32k`** plus OLS `contextWindowSize`/`maxTokensForResponse` — with the default 8k context, OLS (system + RAG + 24 MCP tools + `max_completion_tokens=4096`) exceeds the window and vLLM returns **400**, which OLS surfaces as `incomplete chunked read`.


---

## 3. Provider type: `openai` not `rhoai_vllm`

| Approach | Why |
|----------|-----|
| `type: openai` + MaaS `/v1` URL | MaaS gateway is OpenAI-compatible; matches [IBM OLS + Model Gateway pattern](https://community.ibm.com/community/user/blogs/christo-abraham/2026/04/17/ols-integrating-model-gateway-and-cas-mcp) |
| `type: rhoai_vllm` + direct vLLM route | Skips MaaS auth, quotas, and telemetry — not the PoC story |

Lightspeed sends chat completions to `${MAAS_URL}/v1` with model `qwen3-4b-instruct` (unified BBR from Day 4 + Day 7 Qwen route).

---

## 4. MaaS wiring for Qwen

| Resource | Purpose |
|----------|---------|
| `MaaSModelRef/qwen3-4b-instruct` | Register pre-existing LLMIS on MaaS |
| `HTTPRoute/bbr-qwen3-4b-instruct` | Body-based routing for unified `/v1/chat/completions` |
| `demo-openshift-lightspeed` subscription | Qwen only, 50k TPM/min |
| `demo-lightspeed-access` auth policy | Authenticated access to Qwen |

---

## 5. Dedicated subscription for Lightspeed

| Field | Value |
|-------|-------|
| Subscription | `demo-openshift-lightspeed` |
| Model | `qwen3-4b-instruct` only |
| TPM limit | 50,000 / min |
| Cost center | `CC-LIGHTSPEED-4001` |
| API key | Minted → `lightspeed-maas.env` |

Lightspeed’s MaaS API key is stored in `openshift-lightspeed/maas-gateway-api-key` secret (`apitoken` key per OLS docs).

---

## 6. Operator prerequisite

| Requirement | Cluster state |
|-------------|---------------|
| `lightspeed-operator` CSV Succeeded | **Already installed** (pre-existing) |
| `OLSConfig` named `cluster` | Created by Day 7 |
| `lightspeed-app-server` deployment | Ready after ~2.5 min |

No additional operator install required on this sandbox.

---

## 7. RBAC note

By default, **cluster-admin / kubeadmin** can use Lightspeed in the console. Other users need explicit RBAC (see [Red Hat OLS RBAC docs](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/html/configure/ols-configuring-openshift-lightspeed#ols-rbac)). For the optional demo, present as **cluster-admin**.

---

## 8. Optional demo placement

Documented in [05-demonstration-steps.md](../05-demonstration-steps.md) under **“Drink your own champagne”** — not part of core slide track (Slides 3–6).

---

## 9. Qwen vLLM tool calling (Lightspeed prerequisite)

OpenShift Lightspeed sends `tool_choice: "auto"`. Qwen’s vLLM server must expose:

| Flag | Value |
|------|-------|
| `--enable-auto-tool-choice` | (no value) |
| `--tool-call-parser` | `hermes` |

These flags are **pre-configured** on the cluster’s `qwen3-4b-instruct` LLMInferenceService (GitOps-deployed). Day 7 does not patch Qwen — only registers it on MaaS and points OLSConfig at it.

---

## 10. Day 7 exit criteria

| Criterion | Result |
|-----------|--------|
| Qwen MaaSModelRef Ready | **Pass** |
| OLSConfig points to MaaS gateway + Qwen | **Pass** |
| MaaS key probe HTTP 200 | **Pass** |
| MaaS `tool_choice: auto` probe HTTP 200 | **Pass** |
| `lightspeed-app-server` Ready | **Pass** |
| Console plugin pod Running | **Pass** |
| Live Lightspeed chat validated | **Manual** — use console |

---

## 11. Files updated

| File | Change |
|------|--------|
| [manifests/qwen-maas-modelref.yaml](manifests/qwen-maas-modelref.yaml) | Register Qwen on MaaS |
| [manifests/bbr-qwen-httproute.yaml](manifests/bbr-qwen-httproute.yaml) | Unified BBR for Qwen |
| [manifests/demo-lightspeed-subscription.yaml](manifests/demo-lightspeed-subscription.yaml) | Qwen model ref |
| [manifests/olsconfig-maas-gateway.yaml](manifests/olsconfig-maas-gateway.yaml) | Default model Qwen |
| [run-day7-install.sh](run-day7-install.sh) | Qwen MaaS wiring + validation |
| [05-demonstration-steps.md](../05-demonstration-steps.md) | Optional “Drink your own champagne” section |
| [README.md](../README.md) | Day 7 index |
| [04-installation-and-ready-state.md](../04-installation-and-ready-state.md) | Day 7 section |

**Removed:** `granite-tool-calling-patch.yaml` (Granite no longer used for Lightspeed). **No day-8** — model selection consolidated into Day 7.
