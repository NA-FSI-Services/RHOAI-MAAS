# Embeddings support in RHOAI Models-as-a-Service

Facts about OpenAI-compatible `/v1/embeddings` through Models-as-a-Service (MaaS) on Red Hat OpenShift AI 3.4 and 3.5, plus the in-progress 3.6 work. Jira statuses were captured **2026-08-24**.

This document covers product support, published APIs, open and closed Jiras, and upstream source. It does not evaluate any particular lab or demonstration.

---

## Current support state

| Stream | First-class MaaS embeddings | What exists today |
|--------|-----------------------------|-------------------|
| **RHOAI 3.4** | Not GA. Strategy/RFE still open. | MaaS docs list `POST /llm/{model-name}/v1/embeddings`. vLLM on MaaS is Technology Preview. Catalog text-embedding models are a separate TP (deploy on vLLM; not automatically MaaS-published). |
| **RHOAI 3.5** (including 3.5 EA) | Not GA. Same RFE/strategy. Engineering epic targets **3.6 EA2**. | Same documented MaaS embeddings API as 3.4. The `/llm/{model-name}/...` path in those docs is incorrect for current gateway routing. Spike-validated: **LLMInferenceService** path-based routing and LLMISVC body-based routing (BBR) for embeddings already work. **ExternalModel** cloud embeddings via IPP `/v1/embeddings` allowlist is still in progress. |
| **RHOAI 3.6 EA2** (planned) | Engineering slice [RHOAIENG-84034](https://redhat.atlassian.net/browse/RHOAIENG-84034): gateway routing, token-rate-limit validation, E2E, docs. | Full strategy [RHAISTRAT-2248](https://redhat.atlassian.net/browse/RHAISTRAT-2248) also includes IPP provider translation, dashboard discovery, and AutoRAG. Those items are **out of scope** for 84034. |

**Product statement:** embeddings as a first-class MaaS feature (capability metadata, ExternalModel BBR, rate-limit validation, E2E, published docs) is **not complete** in 3.4 or 3.5. On-platform LLMISVC embeddings through the existing gateway have been spike-validated; remaining 3.6 EA2 work is ExternalModel/IPP, TRLP/observability, tests, and documentation.

---

## Documented MaaS inference API

3.4 and 3.5 MaaS documentation both describe the same embeddings operation:

- **Method / path (as published):** `POST /llm/{model-name}/v1/embeddings`
- **Auth:** API key with `sk-oai-` prefix (same as chat completions)
- **Purpose:** generate text embeddings
- **Response:** OpenAI embeddings schema (`object: list`, `data[].embedding`, `usage.prompt_tokens`)

Example from the published API:

```http
POST https://<maas-gateway-url>/llm/<model-name>/v1/embeddings
Authorization: Bearer sk-oai-...
Content-Type: application/json

{"model": "<model-name>", "input": "The quick brown fox"}
```

Sources:

- [RHOAI 3.4 — Govern LLM access with Models-as-a-Service](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service_maas) (section `POST /llm/{model-name}/v1/embeddings`)
- [RHOAI 3.5 — Govern LLM access with Models-as-a-Service](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service) (same section)

`maas-api` OpenAPI (`maas-api/openapi3.yaml`) covers control-plane endpoints (`/v1/models`, subscriptions, keys). It does **not** define `/v1/embeddings`. Inference paths are gateway HTTPRoutes, not maas-api.

### Path that actually matches HTTPRoutes

[RHOAIENG-81184](https://redhat.atlassian.net/browse/RHOAIENG-81184) (Resolved) and [RHOAIENG-83136](https://redhat.atlassian.net/browse/RHOAIENG-83136) (Resolved) record that documented `/llm/{model-name}/v1/completions` and `/llm/{model-name}/v1/embeddings` return **404**. Working path-based form:

```text
https://<maas-gateway-url>/{namespace}/{model-name}/v1/embeddings
```

81184 workaround text: `https://<maas-gateway-url>/<deployed-model-namespace>/<model-name>/v1`.

Epic 84034 acceptance uses `POST /{namespace}/{model}/v1/embeddings` and, separately, LLMISVC BBR `POST /v1/embeddings` with a publisher model ID.

---

## Adjacent features that are not first-class MaaS embeddings

These ship in 3.4/3.5 but are **not** the MaaS embeddings RFE.

### vLLM on MaaS (Technology Preview)

Enables deploying vLLM via `LLMInferenceService` through the MaaS dashboard and applying MaaS auth/subscriptions to those models. Flag:

```yaml
spec:
  dashboardConfig:
    vLLMDeploymentOnMaaS: true   # OdhDashboardConfig
```

This is the serving path used for on-platform models (including pooling/embedding runtimes). It is **not** by itself a completed embeddings product feature.

| Item | Status | Notes |
|------|--------|--------|
| [RHAISTRAT-1167](https://redhat.atlassian.net/browse/RHAISTRAT-1167) Enable vLLM Runtime Support in MaaS | Release Pending | fixVersion `rhoai-3.4` (released 2026-05-14) |
| [RHOAIENG-52199](https://redhat.atlassian.net/browse/RHOAIENG-52199) vLLM on MaaS: Add feature flag | Closed | Dashboard flag |
| [RHOAIENG-56046](https://redhat.atlassian.net/browse/RHOAIENG-56046) vLLM on MaaS: e2e test | Closed | |

Dashboard implementation: [opendatahub-io/odh-dashboard#6629](https://github.com/opendatahub-io/odh-dashboard/pull/6629).

Docs: 3.4 and 3.5 MaaS deploy chapters; [3.5 TP notes — vLLM runtime support for Models-as-a-Service](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/technology-preview-features_relnotes).

### Model Catalog text-embedding models (Technology Preview)

Separate TP: discover and deploy embedding ModelCar images on vLLM from the catalog (`text-embedding` tag under Other models). Models listed in 3.4/3.5 TP notes include Granite Embedding English R2, Embedding Gemma 300M, Nomic Embed Text v1.5, Qwen3 Embedding 8B, All-MiniLM-L6-v2.

Catalog deployment does **not** automatically register the model as a MaaS-published gateway service.

Source: [3.4 TP features](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes/technology-preview-features_relnotes), [3.5 TP features](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/technology-preview-features_relnotes).

### Single-model serving `/v1/embeddings` (not MaaS)

The single-model serving platform documents OpenAI-compatible `/:443/v1/embeddings` on the vLLM runtime. That endpoint requires a vLLM-supported embeddings model; generative models cannot serve it.

Source: [Making inference requests to deployed models (3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/deploying_models/making_inference_requests_to_deployed_models).

### Llama Stack / OGX embeddings (Technology Preview)

Llama Stack documents `/v1/embeddings` against configured embedding providers. Custom embeddings on OGX (`VLLM_EMBEDDING_URL` on `OGXServer`) are a separate TP. These are not the MaaS gateway RFE.

---

## On-platform serving path for embedding models

Field and engineering notes agree on this split:

| Workload | Typical MaaS serving | Embeddings-related constraint |
|----------|----------------------|-------------------------------|
| Chat / generation | llm-d (`LLMInferenceService` with router/scheduler) | Generation HTTPRoutes historically matched chat/completions paths |
| Embeddings | Plain vLLM pooling, **omit** `router.scheduler` | vLLM 0.18 removed `--task embed`; current flag is `--runner pooling` |

Verified walkthrough (community, not product docs): [rh-aiservices-bu/RHOAI-MaaS-Embedding-Model](https://github.com/rh-aiservices-bu/RHOAI-MaaS-Embedding-Model) (`BAAI/bge-base-en-v1.5`, pooling runner, no scheduler).

llm-d Endpoint Picker later gained `/v1/embeddings` parsing (Gateway API Inference Extension, 2026-03): [kubernetes-sigs/gateway-api-inference-extension#2419](https://github.com/kubernetes-sigs/gateway-api-inference-extension/commit/251163fef6abed9542eb5d7012e6b98b08c5de9c) (`EmbeddingsRequest`, OpenAI parser path `/v1/embeddings`). Field examples still treat embeddings as vLLM-without-scheduler.

84034 operator notes: KServe enabled in the DataScienceCluster; vLLM **v0.24.0+**.

---

## ExternalModel and IPP

Embeddings are **not** ExternalModel-only. The same client URL shape applies to:

1. In-cluster pooling vLLM behind an LLMISVC HTTPRoute (spike-validated).
2. ExternalModel backends **if** IPP allows `/v1/embeddings` and the upstream provider exposes embeddings.

IPP OpenAI provider docs currently describe chat pass-through (`apiFormat: openai-chat`, path `/v1/chat/completions`) only:

- [opendatahub-io/ai-gateway-payload-processing `docs/providers/openai.md`](https://github.com/opendatahub-io/ai-gateway-payload-processing/blob/main/docs/providers/openai.md)
- [models-as-a-service `docs/content/install/external-model-setup.md`](https://github.com/opendatahub-io/models-as-a-service/blob/b6ad6ade/docs/content/install/external-model-setup.md)

[RHOAIENG-84035](https://redhat.atlassian.net/browse/RHOAIENG-84035) remaining work:

- Add `/v1/embeddings` to `detectInputAPIFormat` plus `OpenAIEmbeddings` API format in IPP
- Unit tests in `plugin_test.go`
- Bump IPP image pin in MaaS (`params.env`, payload-processing kustomization)

Strategy [RHAISTRAT-2248](https://redhat.atlassian.net/browse/RHAISTRAT-2248) additionally plans per-provider embedding translation (Bedrock, Vertex, Cohere) and `model-capabilities: embeddings` on MaaSModelRef/ExternalModel. Those are **not** in the 84034 3.6 EA2 slice.

Path-based ExternalModel HTTPRoute (legacy/current controller): `/{namespace}/{modelName}` plus header `X-Gateway-Model-Name` — [maas-controller `pkg/reconciler/externalmodel/resources.go`](https://github.com/opendatahub-io/models-as-a-service/blob/b6ad6ade/maas-controller/pkg/reconciler/externalmodel/resources.go).

---

## Jira

### Product / strategy (open)

| Key | Type | Summary | Status | Notes |
|-----|------|---------|--------|-------|
| [RHAIRFE-2680](https://redhat.atlassian.net/browse/RHAIRFE-2680) | Feature Request | Embedding model support in Model as a Service (MaaS) | Approved | Source RFE |
| [RHAISTRAT-2248](https://redhat.atlassian.net/browse/RHAISTRAT-2248) | Feature | Embedding model support in Model as a Service (MaaS) | New | Clones 2680. Gateway routing, IPP translation, `/v1/models` capability discovery, AutoRAG, dashboard. P0 is gateway + ExternalModel/platform-served embeddings; AutoRAG/dashboard are P1. |

### Engineering epic and stories (3.6 EA2 slice)

| Key | Type | Summary | Status |
|-----|------|---------|--------|
| [RHOAIENG-84034](https://redhat.atlassian.net/browse/RHOAIENG-84034) | Epic | Embedding model support — gateway, validation, E2E, docs (3.6 EA2) | In Progress |
| [RHOAIENG-84035](https://redhat.atlassian.net/browse/RHOAIENG-84035) | Story | ExternalModel BBR for `/v1/embeddings` + IPP rollout | Review |
| [RHOAIENG-84036](https://redhat.atlassian.net/browse/RHOAIENG-84036) | Story | Validate TRLP on embeddings + observability path matchers | In Progress |
| [RHOAIENG-84037](https://redhat.atlassian.net/browse/RHOAIENG-84037) | Story | E2E test coverage for embedding model inference | In Progress |
| [RHOAIENG-84038](https://redhat.atlassian.net/browse/RHOAIENG-84038) | Story | Documentation: embedding deployment guide + BBR fix | In Progress |

84034 **out of scope:** cloud provider translation, Dashboard, AutoRAG, vLLM image GA.

Proposal tree cited by 84034/84035: `https://github.com/opendatahub-io/models-as-a-service/tree/main/docs/proposals/jira-embedding` (not present on `main` as of 2026-08-24; Jira still links `story-gateway-routing.jira`).

### Related (not in 84034)

| Key | Type | Summary | Status | Relation |
|-----|------|---------|--------|----------|
| [RHOAIENG-79228](https://redhat.atlassian.net/browse/RHOAIENG-79228) | Epic | [AutoRAG] MaaS embeddings adoption — remove embedding_model_secret_name | New | Explicitly out of 84034 |
| [RHOAIENG-50823](https://redhat.atlassian.net/browse/RHOAIENG-50823) | Task | Sanity check on embedding models | Backlog | Serving/catalog, not MaaS gateway |

### Closed / resolved (docs path and vLLM-on-MaaS)

| Key | Type | Summary | Status | Outcome |
|-----|------|---------|--------|---------|
| [RHOAIENG-81184](https://redhat.atlassian.net/browse/RHOAIENG-81184) | Bug | Chat completions and embedding endpoints don't work | Resolved | Docs path `/llm/...` vs working `/{namespace}/{model}/...` |
| [RHOAIENG-83136](https://redhat.atlassian.net/browse/RHOAIENG-83136) | Bug | Invalid BBR endpoints referenced in the docs | Resolved | Same `/llm/` docs issue (3.5 / 3.6-EA1) |
| [RHOAIENG-52199](https://redhat.atlassian.net/browse/RHOAIENG-52199) | | vLLM on MaaS: Add feature flag | Closed | Flag shipped |
| [RHOAIENG-56046](https://redhat.atlassian.net/browse/RHOAIENG-56046) | | vLLM on MaaS: e2e test | Closed | |
| [RHAISTRAT-1167](https://redhat.atlassian.net/browse/RHAISTRAT-1167) | Feature | Enable vLLM Runtime Support in MaaS | Release Pending | 3.4 TP |

---

## Source code and repositories

| Area | Location |
|------|----------|
| MaaS controllers, HTTPRoutes, CRDs | [opendatahub-io/models-as-a-service](https://github.com/opendatahub-io/models-as-a-service) |
| ExternalModel HTTPRoute builder | [`maas-controller/pkg/reconciler/externalmodel/resources.go`](https://github.com/opendatahub-io/models-as-a-service/blob/b6ad6ade/maas-controller/pkg/reconciler/externalmodel/resources.go) |
| Control-plane OpenAPI (no embeddings path) | [`maas-api/openapi3.yaml`](https://github.com/opendatahub-io/models-as-a-service/blob/main/maas-api/openapi3.yaml) |
| IPP plugins (`detectInputAPIFormat`, api-translation, apikey-injection) | [opendatahub-io/ai-gateway-payload-processing](https://github.com/opendatahub-io/ai-gateway-payload-processing) |
| IPP OpenAI provider (chat pass-through today) | [`docs/providers/openai.md`](https://github.com/opendatahub-io/ai-gateway-payload-processing/blob/main/docs/providers/openai.md) |
| vLLM-on-MaaS dashboard flag | [odh-dashboard PR 6629](https://github.com/opendatahub-io/odh-dashboard/pull/6629) |
| EPP `/v1/embeddings` parser | [GIE commit 251163f](https://github.com/kubernetes-sigs/gateway-api-inference-extension/commit/251163fef6abed9542eb5d7012e6b98b08c5de9c) (`pkg/epp/framework/plugins/requesthandling/parsers/openai/openai.go`) |
| Pooling vLLM LLMISVC example | [rh-aiservices-bu/RHOAI-MaaS-Embedding-Model](https://github.com/rh-aiservices-bu/RHOAI-MaaS-Embedding-Model) |

---

## 3.4 vs 3.5 vs planned 3.6 (compact)

| Capability | 3.4 | 3.5 | 3.6 EA2 (in progress) |
|------------|-----|-----|------------------------|
| MaaS docs list `POST .../v1/embeddings` | Yes (`/llm/{model}/...`) | Yes (same path; 81184/83136: incorrect) | 84038: inference guide + BBR path fix |
| vLLM on MaaS | TP (`vLLMDeploymentOnMaaS`) | TP | Still TP; vLLM image GA out of 84034 |
| Catalog text-embedding models | TP | TP | Unchanged by 84034 |
| LLMISVC path-based `/v1/embeddings` | Not a completed MaaS feature | Spike-validated (84035) | Regression-guarded in 84035/84037 |
| ExternalModel `POST /v1/embeddings` via IPP | Not supported in IPP OpenAI allowlist | Same; 84035 in Review | Target of 84035 |
| TRLP / observability on embeddings | Not validated as a MaaS embeddings feature | Same | 84036 |
| E2E (path, BBR, 429, 403) | No embeddings E2E in 84034 sense | No | 84037 |
| `/v1/models` `model-capabilities: embeddings` | Strategy only | Strategy only | RHAISTRAT-2248; not in 84034 |
| AutoRAG uses MaaS embeddings | No | No (79228 New) | Out of 84034 |
