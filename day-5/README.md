# Day 5 Installation Results

**Completed:** 2026-06-05  
**External provider:** Red Hat workshop LiteLLM proxy  
**Model:** `codellama-7b-instruct`

---

## Summary

Day 5 integrates an **external OpenAI-compatible model** through the MaaS gateway using the native `ExternalModel` CR (Technology Preview). The upstream LiteLLM endpoint is fronted by MaaS governance: MaaS API keys, subscriptions, and Authorino auth — while the workshop provider key stays in a cluster secret.

| Criterion | Result |
|-----------|--------|
| ExternalModel + routes created | **Pass** |
| Provider key injection | **Pass** (requires BBR-managed secret label) |
| Model path inference (basic key) | **Pass** — HTTP 200 |
| Model path inference (advanced key) | **Pass** — HTTP 200 |
| No auth on model path | **Pass** — HTTP 401 |
| Unified `/v1/chat/completions` | **Fail** — use model path (see [CHANGES.md](CHANGES.md)) |

---

## Integration instructions

### Prerequisites

- Days 1–4 complete (MaaS gateway, BBR, API keys)
- Cluster egress to `maas-rhdp.apps.maas.redhatworkshops.io`
- LiteLLM workshop API key (scoped to `codellama-7b-instruct`)
- `ExternalModel` CRD available (`oc get crd externalmodels.maas.opendatahub.io`)

### Quick install

```bash
cd PoC/day-5

# 1. Set provider key (never commit)
cp provider-key.env.example provider-key.env
# edit provider-key.env → export LITELLM_PROVIDER_KEY="sk-..."

# 2. Run install
chmod +x run-day5-install.sh
./run-day5-install.sh
```

### Manual install (step-by-step)

```bash
export LITELLM_PROVIDER_KEY="sk-..."   # workshop key

# Provider secret — MUST have BBR-managed label
oc create secret generic litellm-workshop-provider-key \
  --from-literal=api-key="${LITELLM_PROVIDER_KEY}" -n llm
oc label secret litellm-workshop-provider-key -n llm \
  inference.networking.k8s.io/bbr-managed=true

# External model registration
oc apply -f manifests/external-model.yaml
oc apply -f manifests/maas-model-ref.yaml

# Governance: subscriptions + auth
oc apply -f manifests/subscription-patches.yaml
oc apply -f manifests/auth-policy-patches.yaml

# Path rewrite for LiteLLM
oc apply -f manifests/httproute-urlrewrite-patch.yaml
```

### Verify

```bash
source ../day-3/demo-env.sh

curl -s -X POST "${MAAS_URL}/llm/codellama-7b-instruct/v1/chat/completions" \
  -H "Authorization: Bearer ${BASIC_USER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "codellama-7b-instruct",
    "messages": [{"role": "user", "content": "Hello from MaaS external model"}],
    "max_tokens": 30
  }' | jq .
```

**Expected:** HTTP 200, LiteLLM response in `choices[0].message.content`.

### Architecture

```
App (MaaS API key)
  → MaaS Gateway (Authorino + quotas)
  → payload-pre-processing (model header)
  → payload-processing (apikey-injection → workshop key)
  → LiteLLM (litellm-prod.apps.maas.redhatworkshops.io)
  → codellama-7b-instruct
```

---

## Demo endpoints

| Use case | URL | `"model"` field |
|----------|-----|-----------------|
| External model (recommended) | `${MAAS_URL}/llm/codellama-7b-instruct/v1/chat/completions` | `codellama-7b-instruct` |
| List models (direct LiteLLM) | `https://maas-rhdp.apps.maas.redhatworkshops.io/v1/models` | (admin only; use workshop key) |

---

## File index

| File | Description |
|------|-------------|
| [CHANGES.md](CHANGES.md) | Plan deviations and fixes |
| [run-day5-install.sh](run-day5-install.sh) | Repeatable install script |
| [provider-key.env.example](provider-key.env.example) | Provider key template (copy to `provider-key.env`) |
| [manifests/external-model.yaml](manifests/external-model.yaml) | ExternalModel CR |
| [manifests/maas-model-ref.yaml](manifests/maas-model-ref.yaml) | MaaSModelRef |
| [manifests/subscription-patches.yaml](manifests/subscription-patches.yaml) | Subscription updates |
| [manifests/auth-policy-patches.yaml](manifests/auth-policy-patches.yaml) | MaaSAuthPolicy updates |
| [manifests/httproute-urlrewrite-patch.yaml](manifests/httproute-urlrewrite-patch.yaml) | LiteLLM path rewrite |
| [05-validation.txt](05-validation.txt) | Validation output |

---

## Security note

Do **not** commit `provider-key.env` or the LiteLLM workshop key. Users authenticate with MaaS API keys only; the provider key is platform-managed in Kubernetes.

> **Advanced Guardrails:** External model routing is orthogonal to content policy. The same org/role guardrail packs (Day 4/6) apply conceptually to prompts destined for `ExternalModel` backends — see [09-advanced-guardrails-plan.md](../09-advanced-guardrails-plan.md).

See [CHANGES.md](CHANGES.md) for the BBR secret label requirement and unified-path limitation.
