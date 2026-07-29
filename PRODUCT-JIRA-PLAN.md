# RHOAI 3.5 EA — Product Jira summary and plan

Tracking Gen AI Studio / MaaS defects found during the RHOAI **3.5 EA** PoC sandbox install.  
Cluster class: OpenShift + RHOAI `rhods-operator` **3.5.0-ea.2**.

**Lab aliases** (see gitignored `LAB-CLUSTERS.md` for credentials/URLs):

| Alias | Role |
|-------|------|
| **tkxcq** | Client-shared cluster — leave as-is |
| **p5ftb** | Clean-room reinstall to confirm which Jiras to open |

> Do not put customer identifiers or live credentials in this file. Use generic terms (*enterprise PoC*, *LOB persona*).

---

## Already open

| Key | Summary | Priority | Customer flag | Component | Status |
|-----|---------|----------|---------------|-----------|--------|
| [RHOAIENG-79529](https://redhat.atlassian.net/browse/RHOAIENG-79529) | Gen AI Studio playground auto-config uses fake MaaS API tokens and invalid model base URLs (RHOAI 3.5 EA) | Major | **Customer Facing** | Gen AI Studio | New |
| [RHOAIENG-79530](https://redhat.atlassian.net/browse/RHOAIENG-79530) | Gen AI Studio playground chat HTTP 500 when TrustyAI CRDs are absent (NeMo discovery hard-fails) | Major | **Customer Facing** | Gen AI Studio | New |
| [RHOAIENG-79549](https://redhat.atlassian.net/browse/RHOAIENG-79549) | MaaS BBR `/v1/chat/completions`: subscription auth rejects short `X-Gateway-Model-Name` (works on `/llm/<model>/...`) | Major | **Customer Facing** | Model as a Service | New |
| [RHOAIENG-79550](https://redhat.atlassian.net/browse/RHOAIENG-79550) | MaaS payload-processing ExtProc attaches to data-science-gateway and breaks RHOAI Observe PromQL (`invalid character 'q'`) | Major | **Customer Facing** | Model as a Service | New |
| [RHOAIENG-79551](https://redhat.atlassian.net/browse/RHOAIENG-79551) | data-science-gateway default 1Gi memory limit causes OOMKilled / `rh-ai` HTTP 503 under Observe load | Major | **Customer Facing** | AI Core Dashboard | New |

### What each covers

**79529 — Playground install / auto-config**

- Symptom: models show “unavailable”; OGX uses `VLLM_API_TOKEN_*=fake`; bad in-cluster `base_url`; wrong `provider_model_id`.
- Workaround: `./scripts/fix-genai-playground-maas.sh <ns> <subscription>` (do not click “Update playground configuration” after).
- Local docs: [06-troubleshooting.md](06-troubleshooting.md#gen-ai-playground--models-unavailable-fake-api-token), [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md).
- Filed from: **tkxcq**. Re-verify via UI on **p5ftb** still pending.

**79530 — TrustyAI hard dependency for chat**

- Symptom: `POST /gen-ai/api/v1/lsd/responses` → 500: `failed to list NemoGuardrails CRs` when TrustyAI is `Removed`.
- Workaround: set DSC `trustyai.managementState: Managed` (NeMo CR optional).
- Docs gap: TrustyAI is documented for NeMo Guardrails, not as a playground chat prerequisite.
- Local docs: same troubleshooting section; [day-2/manifests/datasciencecluster-3.5-ea.yaml](day-2/manifests/datasciencecluster-3.5-ea.yaml).
- Filed from: **tkxcq**. **p5ftb** has TrustyAI Managed (do not re-break unless needed).

**79549 (plan A) — BBR short model-name auth**

- Symptom: path `/llm/<model>/...` → **200**; unified `/v1/chat/completions` with short `model` / `X-Gateway-Model-Name` → **403** (`does not include model <short-name>`). Auth lists use `llm/<model>`.
- Reproduced on **p5ftb** with `maas-controller` replicas=**1**.
- Workaround: use path URLs; or AuthPolicy short-name aliases + pause controller (PoC only).
- Local docs: [06-troubleshooting.md](06-troubleshooting.md) (BBR / auth sections), [day-4/CHANGES.md](day-4/CHANGES.md).

**79550 (plan B) — IPP ExtProc on data-science-gateway**

- Symptom: Observe/Perses PromQL → `invalid character 'q'`; ExtProc/`payload-processing` present on DSG `config_dump`. Stock IPP NetworkPolicy allows DSG but not always `maas-default-gateway` (MaaS `/maas-api` ExtProc timeout until NP patch).
- Workaround: EnvoyFilter `workloadSelector` for `maas-default-gateway` only; NP allowing MaaS gateway → IPP.
- Local docs: [06-troubleshooting.md](06-troubleshooting.md#observability-dashboard--invalid-character-q--ipp-badrequest), [day-5/CHANGES.md](day-5/CHANGES.md).

**79551 (plan C) — data-science-gateway 1Gi OOM**

- Symptom: default memory limit **1Gi**; under Observe load OOMKilled (`exitCode: 137`) → `rh-ai` **503**.
- Confirmed default **1Gi** on **p5ftb**; capture exit 137 when Observe is load-tested.
- Workaround: `./day-2/fix-data-science-gateway-memory.sh` → **2Gi**.
- Local docs: [06-troubleshooting.md](06-troubleshooting.md#rhoai-dashboard-rh-ai-not-responding--http-503).

### Cross-links already noted in tickets

- Related (not duplicates): [RHOAIENG-69083](https://redhat.atlassian.net/browse/RHOAIENG-69083), [RHOAIENG-38779](https://redhat.atlassian.net/browse/RHOAIENG-38779).
- Coupling theme: [RHAIRFE-2897](https://redhat.atlassian.net/browse/RHAIRFE-2897) / [RHAISTRAT-2379](https://redhat.atlassian.net/browse/RHAISTRAT-2379).
- Playground vs gateway: 79529/79530 are Gen AI Studio; 79549–79551 are MaaS / console gateway.

---

## Optional / not opened yet

| # | Working title | Why defer | Local workaround today |
|---|---------------|-----------|------------------------|
| **D** | ExternalModel / IPP: undocumented secret labels, NetworkPolicy, ExtProc attach, `GATEWAY_NAME` | File only if PoC demos external / LiteLLM with the client | Manifests under `day-5/manifests/` |

### Out of scope for new bugs (for now)

| Topic | Reason |
|-------|--------|
| Empty MaaS usage panels / TelemetryPolicy tuning | Often config; revisit if product defaults remain empty after A–C |
| No Gen AI Studio NeMo policy editor | TP limitation → RFE, not install blocker |
| Self-deploy Llama KV / `max_model_len` on L4 | Expected sizing; answer with guidance, not a product defect from our install |

---

## Filing record (A/B/C)

| Plan | Key | Filed | Confirmed on |
|------|-----|-------|--------------|
| **A** | [RHOAIENG-79549](https://redhat.atlassian.net/browse/RHOAIENG-79549) | 2026-07-28 | **p5ftb** (path 200 vs BBR 403; controller=1) |
| **B** | [RHOAIENG-79550](https://redhat.atlassian.net/browse/RHOAIENG-79550) | 2026-07-28 | **p5ftb** (ExtProc on DSG config_dump; PromQL `'q'` from tkxcq write-up) |
| **C** | [RHOAIENG-79551](https://redhat.atlassian.net/browse/RHOAIENG-79551) | 2026-07-28 | **p5ftb** (default 1Gi); OOM 137 still to capture under load |

### Hygiene after filing

| Action | Status |
|--------|--------|
| Add ticket keys to this plan | **done** |
| Add keys to [06-troubleshooting.md](06-troubleshooting.md) “Related” lines | pending |
| Do **not** commit filled `CLIENT-TEST-ACCESS.md` | ongoing |
| Restore `maas-controller` replicas=1 on **tkxcq** after demos | pending (document scale state) |
| Comment on 79529/79530 that BBR auth is separate (79549) | **done** |

---

## Confirmation on clean cluster **p5ftb**

| Validation step | Confirms Jira | Result |
|-----------------|---------------|--------|
| Deploy Llama/Gemma; Ready on L4 | sizing/docs only | Llama Ready; Gemma still downloading |
| Day-6 LOB users + path `/llm/...` matrix | baseline | Pass (retail/risk) |
| Prompt via unified BBR `/v1/chat/completions` | **79549** | **Filed** — short name → 403 |
| Gen AI playground first create | **79529** | UI re-verify pending |
| Playground chat with TrustyAI Removed | **79530** | Skip while TrustyAI Managed |
| Observe / Perses after IPP | **79550** | **Filed** — ExtProc attach confirmed |
| `rh-ai` under Observe load | **79551** | **Filed** — default 1Gi confirmed |
| External LiteLLM (optional) | **D** | Not opened |

---

## Checklist

- [x] Open playground auto-config bug → **RHOAIENG-79529** (tkxcq)
- [x] Open TrustyAI playground 500 bug → **RHOAIENG-79530** (tkxcq)
- [x] Open BBR short model-name auth bug (**A**) → **RHOAIENG-79549**
- [x] Open Observe ExtProc scope bug (**B**) → **RHOAIENG-79550**
- [x] Open data-science-gateway OOM bug (**C**) → **RHOAIENG-79551**
- [ ] Re-verify 79529 on **p5ftb** (UI Try in playground)
- [ ] Re-verify 79530 on **p5ftb** (only if TrustyAI Removed for test)
- [ ] Optional: external model IPP docs/install bug (**D**)
- [ ] Link new keys from troubleshooting docs
- [ ] Restore or document `maas-controller` scale state on **tkxcq**

---

*Last updated: 2026-07-28 — filed RHOAIENG-79549 / 79550 / 79551 (plan A/B/C).*
