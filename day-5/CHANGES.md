# Day 5 Installation — Change Log and Deviations

**Date:** 2026-06-05  
**Script:** [run-day5-install.sh](run-day5-install.sh)

Records conflicts between the original PoC blueprint and live cluster behavior during Day 5 external model integration.

---

## 1. External model was not in the original 4-day plan

| Original plan | Day 5 resolution |
|---------------|------------------|
| Local Granite + CPU simulator only | Added **ExternalModel** CR routing to Red Hat workshop LiteLLM proxy |
| External Model Egress marked optional/TP in blueprint | Implemented for demo using `codellama-7b-instruct` |

**Upstream:** [RHOAI 3.4 — Configure external models for MaaS](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service_maas#configure-external-models-for-models-as-a-service_maas)

---

## 2. LiteLLM workshop proxy vs native cloud providers

| Field | Value used |
|-------|------------|
| Provider URL | `https://maas-rhdp.apps.maas.redhatworkshops.io/v1` |
| ExternalModel `endpoint` | `maas-rhdp.apps.maas.redhatworkshops.io` (FQDN only, no path) |
| `provider` | `openai` (OpenAI-compatible LiteLLM API) |
| `targetModel` | `codellama-7b-instruct` (only model allowed by workshop key) |

**Discovery:** `GET /v1/models` on the workshop endpoint returns only `codellama-7b-instruct`. Other model names return `key_model_access_denied`.

---

## 3. Provider secret requires IPP/BBR-managed labels (critical fix)

| Symptom | Root cause | Fix |
|---------|------------|-----|
| HTTP 500: `provider 'openai' credentials not found` | `apikey-injection` only watches secrets labeled for IPP/BBR | Label the provider secret before testing |

```bash
oc label secret litellm-workshop-provider-key -n llm \
  inference.networking.k8s.io/bbr-managed=true \
  inference.llm-d.ai/ipp-managed=true --overwrite
```

These labels are **not documented** in the RHOAI external-model procedure but are required by the payload-processing `apikey-injection` reconciler.

---

## 3b. RHOAI 3.5-ea: IPP must reach `maas-default-gateway` (2026-07-28)

| Symptom | Root cause | Fix |
|---------|------------|-----|
| ExtProc `gRPC_error_14` / connect timeout → HTTP 500 | Stock NetworkPolicy only allows `gateway-name=data-science-gateway` | [networkpolicy-payload-processing-maas-gateway.yaml](manifests/networkpolicy-payload-processing-maas-gateway.yaml) |
| No credential injection; MaaS key forwarded to LiteLLM | Stock `EnvoyFilter/payload-processing` matches old Kuadrant WasmPlugin name; ExtProc never attaches | [envoyfilter-payload-processing-extproc-attach.yaml](manifests/envoyfilter-payload-processing-extproc-attach.yaml) |
| HTTPRoute parent `default-gateway` → `route_not_found` | IPP ExternalModel reconciler defaults gateway name | `oc set env deploy/payload-processing GATEWAY_NAME=maas-default-gateway GATEWAY_NAMESPACE=openshift-ingress` |
| Workshop key rejects `codellama-7b-instruct` | Current workshop token only allows `llama-31-70b-cpu` | Use `*-llama-31-70b-cpu.yaml` manifests |
| RHOAI Observe panels: `invalid character 'q' looking for beginning of value` | IPP ExtProc EnvoyFilters used `targetRefs` only; filters attached to **data-science-gateway** as well. Perses PromQL POSTs `query=...` (form body), which IPP tries to parse as JSON | Switch both `payload-processing` and `payload-processing-extproc-attach` to `workloadSelector` for `gateway-name=maas-default-gateway` (OpenShift allows only one of `targetRefs` / `workloadSelector`) |

---

## 4. HTTPRoute URL rewrite required

| Symptom | Root cause | Fix |
|---------|------------|-----|
| Timeouts / 500 to external host | Controller HTTPRoute forwards `/llm/codellama-7b-instruct/v1/...` verbatim | Apply [httproute-urlrewrite-patch.yaml](manifests/httproute-urlrewrite-patch.yaml) |

LiteLLM expects `/v1/chat/completions`, not the MaaS model prefix path.

---

## 5. Two-tier authentication (by design)

| Layer | Credential |
|-------|------------|
| User → MaaS gateway | MaaS API key (`BASIC_USER_KEY` / `ADVANCED_USER_KEY`) |
| Gateway → LiteLLM | Provider key in `litellm-workshop-provider-key` secret (injected by gateway) |

Users never send the LiteLLM workshop key. Administrators store it once in a cluster secret.

---

## 6. Unified BBR vs model-specific path

| Endpoint | Result |
|----------|--------|
| `/llm/codellama-7b-instruct/v1/chat/completions` | **HTTP 200** with MaaS API key |
| `/v1/chat/completions` + `"model":"codellama-7b-instruct"` | **HTTP 401** — MaaS key forwarded to LiteLLM (same Day 4 auth-gap class) |

**Demo guidance:** Use the **model-specific path** for external model inference and auth demos.

---

## 7. Manual steps beyond ExternalModel CR

The RHOAI docs cover ExternalModel + subscription. This cluster also required:

1. **MaaSModelRef** — register external model in MaaS catalog
2. **MaaSAuthPolicy patches** — Authorino policy on external HTTPRoute
3. **MaaSSubscription patches** — add model to `simulator-free` and `granite-tiny-gpu-premium`
4. **Secret label** — `inference.networking.k8s.io/bbr-managed=true`
5. **HTTPRoute URL rewrite** — path normalization for LiteLLM

---

## 8. Day 5 exit criteria scorecard

| Criterion | Target | Result |
|-----------|--------|--------|
| ExternalModel Ready | Created + routes exist | **Pass** |
| Provider secret injected | LiteLLM accepts gateway request | **Pass** (after BBR label) |
| Model path inference | HTTP 200 | **Pass** |
| Basic + advanced MaaS keys | HTTP 200 | **Pass** |
| No auth | HTTP 401 | **Pass** |
| Unified BBR external | HTTP 200 | **Fail** — use model path |
| Workshop key in git | Never committed | **Pass** — use `provider-key.env` |

---

## 9. Files updated in PoC package

| File | Change |
|------|--------|
| [README.md](../README.md) | Day 5 index |
| [02-cluster-current-state.md](../02-cluster-current-state.md) | External model endpoint |
| [04-installation-and-ready-state.md](../04-installation-and-ready-state.md) | Day 5 section |
| [05-demonstration-steps.md](../05-demonstration-steps.md) | Demo 7 external model |
| [06-troubleshooting.md](../06-troubleshooting.md) | BBR secret label, URL rewrite |
