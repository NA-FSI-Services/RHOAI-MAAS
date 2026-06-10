# Operational Troubleshooting and Demo Workarounds

Known issues and recovery procedures for the RHOAI 3.4 MaaS PoC demonstration.

---

## RHOAI OperatorGroup Conflict (GitOps clusters)

### Problem

Applying the full `manifests/01-prerequisites/operators/` kustomize on a GitOps-managed cluster creates a duplicate `OperatorGroup` in `redhat-ods-operator`, causing:

```
rhods-operator CSV Failed: csv created in namespace with multiple operatorgroups
```

### Workaround

Delete the duplicate OperatorGroup (keep the original `rhods-operator` OG):

```bash
oc delete operatorgroup redhat-ods-operator -n redhat-ods-operator
```

On GitOps clusters, apply operators selectively (skip `rhoai-operator/`):

```bash
oc apply -k manifests/01-prerequisites/operators/cert-manager/
oc apply -k manifests/01-prerequisites/operators/connectivity-link/
oc apply -k manifests/01-prerequisites/operators/service-mesh/
oc apply -k manifests/01-prerequisites/operators/leader-worker-set/
```

- [day-2/CHANGES.md](day-2/CHANGES.md) — Day 2 deviations

---

---

## Authorino TLS Certificate Missing (Gateway HTTP 500)

### Problem

Gateway returns HTTP 500 on all model paths. Authorino CR shows `Ready=False` with `TlsSecretNotProvided`. The `authorino-server-cert` secret does not exist.

This was the **root cause** of the Day 2 blocker. Duplicate maas-api cleanup alone does not fix it.

### Symptoms

- `GET /v1/models` → HTTP 500
- Gateway logs: `gRPC status code is not OK`
- API key creation fails with `AUTH_FAILURE` even via port-forward to maas-api
- `oc get authorino authorino -n kuadrant-system` shows TLS secret not found

### Workaround

```bash
cd rhoai-maas-guide
oc apply -f manifests/02-platform-config/kuadrant/service-annotation.yaml

# Wait for serving cert (~10s)
oc get secret authorino-server-cert -n kuadrant-system

oc patch authorino authorino -n kuadrant-system --type=merge --patch '{
  "spec": {"listener": {"tls": {"enabled": true, "certSecretRef": {"name": "authorino-server-cert"}}}}
}'
oc -n kuadrant-system set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt
oc rollout restart deployment/authorino -n kuadrant-system
oc rollout status deployment/authorino -n kuadrant-system --timeout=120s
```

Verify: `GET /v1/models` without auth should return **401** (not 500).

See [day-3/CHANGES.md](day-3/CHANGES.md) for full Day 3 remediation.

---

## Duplicate maas-api Deployments (GitOps clusters)

### Problem

GitOps-managed clusters may have a legacy `maas-api` deployment in the `maas-api` namespace (port 8080, no PostgreSQL) alongside the operator-managed instance in `redhat-ods-applications` (port 8443, DB-connected). Duplicate HTTPRoutes and AuthPolicies cause ambiguous gateway routing.

### Symptoms

- `/maas-api/health` returns 500 or routes to wrong backend
- API key minting fails even when PostgreSQL is running
- Two `maas-api` pods in different namespaces

### Workaround

```bash
# Remove legacy route (keep operator route in redhat-ods-applications)
oc delete httproute maas-api-route -n maas-api 2>/dev/null || true

# Scale down legacy deployment
oc scale deployment maas-api -n maas-api --replicas=0

# Verify health routes to operator instance
export MAAS_URL="https://maas.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
curl -sk -o /dev/null -w "health: HTTP %{http_code}\n" "${MAAS_URL}/maas-api/health"
```

See [day-2/CHANGES.md](day-2/CHANGES.md) for full Day 2 remediation notes. Day 4 cleanup script: [day-4/run-day4-install.sh](day-4/run-day4-install.sh). **GitOps will restore** legacy resources — permanent removal requires updating the `models-as-a-service` ArgoCD application (see [day-4/CHANGES.md](day-4/CHANGES.md)).

---

## Unified BBR Returns 404 or Malformed Path

### Problem

After enabling body-based routing, `POST /v1/chat/completions` returns 404, or requests hit a malformed backend path like `/v1/chat/completionsv1/chat/completions`.

### Symptoms

- Unified endpoint 404 while model-specific paths work
- `payload-pre-processing` pod missing or `ImagePullBackOff`
- EnvoyFilter has only INSERT_AFTER stage (post-processing)

### Workaround

Run Day 4 install or apply manifests manually:

```bash
cd PoC/day-4
./run-day4-install.sh
```

Key fixes:

1. Deploy `payload-pre-processing` with correct image:
   `quay.io/opendatahub/odh-ai-gateway-payload-processing:odh-stable`
2. Apply two-stage EnvoyFilter: [manifests/bbr/envoy-filter-full.yaml](day-4/manifests/bbr/envoy-filter-full.yaml)
3. HTTPRoutes must match **both** path `/v1/chat/completions` **and** header `X-Gateway-Model-Name`; use `ReplaceFullPath` (not `ReplacePrefixMatch`)

See [day-4/CHANGES.md](day-4/CHANGES.md) for full root-cause analysis.

---

## Unified Path Allows Unauthenticated Access (Auth Gap)

### Problem

`POST /v1/chat/completions` without an API key returns HTTP 200, while model-specific paths correctly return 401.

### Workaround for demos

- Use **model-specific paths** (`/llm/.../v1/chat/completions`) for 401/403 auth demonstrations (Demo 2)
- Always send API keys on the unified endpoint in production-style demos

Optional fix: attach AuthPolicies to BBR HTTPRoutes via MaaS controller reconciliation.

See [day-5/CHANGES.md](day-5/CHANGES.md) §2.

---

## External Model — credentials not found (HTTP 500)

### Problem

After creating `ExternalModel` and provider secret, gateway returns:

```
inference error: Internal - provider 'openai' credentials not found
```

### Root cause

The `apikey-injection` plugin in `payload-processing` only loads secrets labeled:

```yaml
inference.networking.k8s.io/bbr-managed: "true"
```

RHOAI external-model docs create the secret but do not mention this label.

### Workaround

```bash
oc label secret litellm-workshop-provider-key -n llm \
  inference.networking.k8s.io/bbr-managed=true --overwrite
oc delete pod -n openshift-ingress -l app=payload-processing
```

See [day-5/CHANGES.md](day-5/CHANGES.md) and [day-5/run-day5-install.sh](day-5/run-day5-install.sh).

---

## External Model — timeouts or wrong path to LiteLLM

### Problem

Requests to `/llm/<external-model>/v1/chat/completions` time out or return 500.

### Workaround

Apply URL rewrite patch so LiteLLM receives `/v1/chat/completions`:

```bash
cd PoC/day-5
oc apply -f manifests/httproute-urlrewrite-patch.yaml
```

---

## External Model — unified BBR returns 401 from LiteLLM

### Problem

`POST /v1/chat/completions` with `"model":"codellama-7b-instruct"` returns LiteLLM auth error mentioning the MaaS API key.

### Workaround

Use the model-specific path for external model demos:

```bash
POST ${MAAS_URL}/llm/codellama-7b-instruct/v1/chat/completions
```

---

## Gateway HTTP 500 on Model Paths (Authorino gRPC)

> **Update (Day 3):** The primary cause is missing `authorino-server-cert`. Apply the Authorino TLS fix above first. The steps below are secondary (Kuadrant reconcile, AuthPolicy checks).

### Problem

After MaaS platform and models are Ready, gateway returns HTTP 500 on model inference paths while `/maas-api/health` may return 200. Gateway logs show Authorino gRPC errors (`gRPC status code is not OK`).

### Symptoms

- `GET /v1/models` → HTTP 500
- `GET /llm/<model>/v1/models` → HTTP 500
- `verify-maas.sh` fails at API key creation (Internal Server Error)
- Model pods and MaaSModelRefs show Ready

### Workaround

1. Remove duplicate maas-api (see above)
2. Restart Kuadrant operator:

```bash
oc rollout restart deployment/kuadrant-operator -n kuadrant-system
oc rollout status deployment/kuadrant-operator -n kuadrant-system --timeout=120s
```

3. Verify Authorino TLS bootstrap annotation on gateway:

```bash
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.metadata.annotations.security\.opendatahub\.io/authorino-tls-bootstrap}{"\n"}'
# Expected: true
```

4. Check AuthPolicies on model HTTPRoutes:

```bash
oc get authpolicy -A
oc get httproute -A | grep -E 'granite|facebook|maas-api'
```

5. Re-run verification:

```bash
cd rhoai-maas-guide
./scripts/verify-maas.sh --no-cleanup
```

---

## setup-maas.sh Phase 5 Skip (Existing Models)

### Problem

If any `LLMInferenceService` exists in the `llm` namespace (e.g., pre-existing Qwen), `setup-maas.sh` skips Phase 5 model deployment.

### Workaround

Deploy models explicitly after setup:

```bash
cd rhoai-maas-guide
./scripts/deploy-model.sh --model granite-tiny-gpu
./scripts/deploy-model.sh --model simulator
```

---

## Gateway Authentication Failure (AUTH_FAILURE)

### Problem

Token generation or validation fails with an `AUTH_FAILURE` error even when using valid API keys. This typically occurs when the Kuadrant operator is deployed in quick succession with Istio and fails to bind the AuthPolicy on first reconciliation.

### Symptoms

- API key minting fails in dashboard
- Valid bearer tokens rejected at gateway
- AuthPolicy shows stale or missing status on gateway

### Workaround

Restart the Kuadrant operator to force full reconciliation:

```bash
oc rollout restart deployment/kuadrant-operator -n kuadrant-system
oc rollout status deployment/kuadrant-operator -n kuadrant-system --timeout=120s
```

Verify AuthPolicy is attached:

```bash
oc get authpolicy -n openshift-ingress
oc describe gateway maas-default-gateway -n openshift-ingress | grep -i authpolicy
```

### Reference

- [models-as-a-service issue #330](https://github.com/opendatahub-io/models-as-a-service/issues/330)

---

## NeMo Guardrails RBAC Access Denied (403 Forbidden)

### Problem (RHOAIENG-60940)

Non-cluster-admin users receive HTTP 403 when accessing or configuring NemoGuardrails resources in the OpenShift console. Caused by missing Kubernetes aggregation labels on the operator's ClusterRoles.

### Symptoms

- Demo user cannot create/view NemoGuardrails CR
- Console shows "Forbidden" for Guardrails resources

### Workaround

Manually bind the editor role to the demo user:

```bash
oc create clusterrolebinding nemo-editor-binding \
  --clusterrole=nemoguardrail-editor-role \
  --user=demo-user-username
```

Replace `demo-user-username` with the actual OpenShift username.

### Reference

- [RHOAI 3.4 Known Issues](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes/known-issues_relnotes)

---

## Prefix Cache Inefficiencies (RHOAIENG-58969)

### Problem

In RHOAI 3.4, the prefix cache scorer identifies routing endpoints using IP **and port**. If the vLLM deployment does not explicitly define the container port, the scorer fails to match cache entries and traffic routing ignores prefix cache locality.

### Symptoms

- EPP always routes to same replica despite repeated prefix prompts
- Prefix-cache-scorer appears inactive in scheduling logs

### Workaround

Ensure the LLMInferenceService spec explicitly defines container port mapping (typically 8000 or 8080):

```yaml
spec:
  template:
    containers:
      - name: main
        ports:
          - containerPort: 8000
            name: http
            protocol: TCP
```

Apply and wait for rollout:

```bash
oc apply -f 05-maas-models/granite-tiny-gpu/serving.yaml
oc rollout status deployment -n llm -l serving.kserve.io/inferenceservice=granite-4-tiny-gpu
```

---

## Wrong MaaS URL — double `apps.` in hostname (SSL / 503)

### Problem

`CLUSTER_DOMAIN` from OpenShift already includes the `apps.` prefix (e.g. `<cluster-domain>`). Using `maas.apps.${CLUSTER_DOMAIN}` produces an invalid hostname:

```text
https://maas.apps.<cluster-domain>   # WRONG
```

### Symptoms

- `curl: (60) SSL: no alternative certificate subject name matches target host name 'maas.apps.apps...'`
- `maas-api/health` returns **503** (wrong host / no route)
- Demo 2 Scenario A never returns **401**

### Fix

```bash
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
export MAAS_URL="https://maas.${CLUSTER_DOMAIN}"   # NOT maas.apps.${CLUSTER_DOMAIN}
export SIM_URL="${MAAS_URL}/llm/facebook-opt-125m-simulated"

echo "MAAS_URL=$MAAS_URL"
# Expected: https://maas.${CLUSTER_DOMAIN}
```

Verify:

```bash
curl -sk -o /dev/null -w "health: HTTP %{http_code}\n" "${MAAS_URL}/maas-api/health"
curl -sk -o /dev/null -w "simulator no-auth: HTTP %{http_code}\n" \
  -X POST "${SIM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Ping"}],"max_tokens":5}'
```

Expected: health **200**, simulator no-auth **401**.

---

## Gateway Returns 503 (Service Unavailable)

### Problem

Unauthenticated or authenticated requests to the MaaS gateway return HTTP 503 (with a **correct** `MAAS_URL` — see double-`apps.` section above first).

### Common Causes

| Cause | Check |
|-------|-------|
| Gateway not programmed | `oc get gateway maas-default-gateway -n openshift-ingress` |
| No HTTPRoute attached | `oc get httproute -A` |
| modelsAsService not Managed | DSC `ModelsAsServiceReady` condition |
| Backend model not ready | `oc get llminferenceservice -A` |
| Missing MaaSModelRef | `oc get maasmodelref -A` |

### Recovery Steps

```bash
# 1. Verify gateway
oc wait --for=condition=Programmed gateway/maas-default-gateway -n openshift-ingress --timeout=120s

# 2. Check MaaS API (operator-managed)
oc get pods -n redhat-ods-applications | grep maas-api
oc logs deploy/maas-api -n redhat-ods-applications --tail=50

# 3. Enable modelsAsService if Removed
oc patch datasciencecluster default-dsc --type=merge -p '
{"spec":{"components":{"kserve":{"modelsAsService":{"managementState":"Managed"}}}}}'

# 4. Re-run gateway setup if needed
cd rhoai-maas-guide
INGRESS_MODE=clusterip ./scripts/setup-gateway.sh
```

---

## maas-db-config Secret Missing

### Problem

MaaS API runs but cannot persist API keys or subscriptions. Dashboard key minting fails.

### Workaround

Deploy PostgreSQL via guide scripts:

```bash
cd rhoai-maas-guide
./scripts/setup-maas.sh --from-phase 4
oc get secret maas-db-config -n redhat-ods-applications
oc rollout status deployment/maas-api -n redhat-ods-applications --timeout=120s
```

---

## Granite Pod Pending (Insufficient GPU)

### Problem

Granite LLMInferenceService pods remain Pending with event: `0/3 nodes are available: 3 Insufficient nvidia.com/gpu`.

### Workaround

1. Verify GPU count: `oc get nodes ... GPUs`
2. If only 1 GPU available, reduce replicas:

```bash
oc patch llminferenceservice granite-4-tiny-gpu -n llm \
  --type=merge -p '{"spec":{"replicas":1}}'
```

3. Request additional GPU workers from infra team (see [04-installation-and-ready-state.md](04-installation-and-ready-state.md))

---

## Rate Limit Demo Not Triggering 429

### Problem

Second large prompt still returns 200 instead of 429.

### Checks

```bash
# Verify TokenRateLimitPolicy on gateway
oc get tokenratelimitpolicy -A
oc describe gateway maas-default-gateway -n openshift-ingress | grep -i ratelimit

# Verify subscription has metric: tokens
oc get maassubscription basic-team-subscription -n models-as-a-service -o yaml

# Check Limitador pod
oc get pods -n kuadrant-system | grep limitador
oc logs deploy/limitador-limitador -n kuadrant-system --tail=30
```

Ensure TPM limit is low enough (e.g., 2000) and prompts are large enough to consume tokens quickly.

---

## Gen AI playground — ConfigMap forbidden (wrong project)

### Problem

Logging in to the RHOAI AI Console as an htpasswd persona and opening **Gen AI studio → Try in playground** fails with:

```text
Error configuring playground
failed to create ConfigMap: configmaps is forbidden: User "demo-retail-analyst"
cannot create resource "configmaps" in API group "" in the namespace "grafana"
```

(The namespace in the message is whichever **project** is selected in the RHOAI UI — often a shared read-only project such as `grafana`.)

### Cause

Gen AI Studio playground stores per-project configuration as **ConfigMaps** (and **Secrets**) in the **OpenShift namespace** tied to the RHOAI **project** you have selected. You need **create** permission in that namespace.

Selecting a project where you only have **`view`** (e.g. a platform monitoring namespace) causes this error. **Do not** grant blanket `edit` on shared namespaces for demo users — use a **dedicated project** instead.

### Fix (recommended — UI)

1. Log in as the persona (`maas-demo-users` IdP).
2. In the RHOAI AI Console, open the **project** drop-down (top navigation) → **Create project**.
3. Enter a dedicated name, for example:

   | Persona | Suggested project name |
   |---------|------------------------|
   | Retail Analyst | `maas-demo-retail` |
   | Risk Analytics | `maas-demo-risk` |
   | Platform Ops | `maas-demo-platform` |

4. Click **Create** — the creator receives **admin** on the new namespace and can create playground ConfigMaps.
5. Ensure the new project is **selected** in the drop-down.
6. **Gen AI studio → AI asset endpoints → Try in playground**.

See [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md#step-01--create-rhoai-projects-before-playground).

### Verify (optional)

```bash
oc auth can-i create configmaps -n maas-demo-retail \
  --as=demo-retail-analyst \
  --as-group=maas-demo-retail-analyst \
  --as-group=system:authenticated
```

Expected: `yes` after the user has created `maas-demo-retail` via the RHOAI UI.

### Alternative (OpenShift Console)

**Home → Projects → Create Project** with the same name while logged in as the persona — equivalent to the RHOAI flow.

See [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md) and [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md).

---

## Observability dashboard — Service Unavailable (Day 6)

### Problem

RHOAI Console → **Observe & monitor → Dashboard** shows:

```text
Error loading components
Service Unavailable
```

Or dashboard loads but panels are empty.

### Fix

Full procedure: **[day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md)**

Quick recovery:

```bash
cd PoC/day-6
oc apply -f manifests/dsci-metrics-storage.yaml
oc apply -f manifests/opentelemetry-operator/subscription.yaml
# wait for pods in redhat-ods-monitoring (data-science-perses, prometheus-...)
./fix-perses-datasource-secret.sh
./daily-traffic.sh --quick
```

### OpenShift Console fallback

MaaS showback metrics (`authorized_hits` with `subscription` labels) can be viewed in **OpenShift Console → Observe → Metrics** (Administrator). The integrated Perses dashboard remains in the **RHOAI** console.

---

## Observability dashboard empty (Day 6)

### Problem

Dashboard loads but shows no data.

### Workaround

Install COO, enable RHOAI observability stack, and apply telemetry:

```bash
cd PoC/day-6
./run-day6-install.sh
./daily-traffic.sh
```

See [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md).

---

## OpenShift Lightspeed — LLM errors or service not Ready

### Problem

Lightspeed console opens but fails to answer, or `lightspeed-app-server` is not Ready.

### Checks

```bash
oc get olsconfig cluster
oc get deploy lightspeed-app-server -n openshift-lightspeed
oc logs -n openshift-lightspeed deploy/lightspeed-app-server -c lightspeed-service-api --tail=30
source day-7/lightspeed-maas.env
curl -s -X POST "${MAAS_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${LIGHTSPEED_MAAS_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-4b-instruct","messages":[{"role":"user","content":"ping"}],"max_tokens":5}'
```

Re-run [day-7/run-day7-install.sh](day-7/run-day7-install.sh) to refresh the MaaS API key.

See [day-7/README.md](day-7/README.md).

---

## OpenShift Lightspeed — `tool_choice auto` HTTP 400

### Problem

Lightspeed returns an LLM error, or MaaS probe fails with:

```text
"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set
```

Lightspeed sends OpenAI-compatible requests with `tool_choice: "auto"`. Day 7 uses **Qwen3-4B-Instruct**, which must have vLLM tool calling enabled.

### Fix

Verify Qwen vLLM args on the running pod:

```bash
QWEN_POD=$(oc get pods -n llm -o name | grep qwen3-4b-instruct-kserve | head -1)
oc get "$QWEN_POD" -n llm -o jsonpath='{.spec.containers[?(@.name=="main")].args}{"\n"}'
```

Expected flags: `--enable-auto-tool-choice` and `--tool-call-parser=hermes`.

Ensure Qwen is registered on MaaS and BBR route exists:

```bash
oc get maasmodelref qwen3-4b-instruct -n llm
oc get httproute bbr-qwen3-4b-instruct -n llm
oc apply -f day-7/manifests/qwen-maas-modelref.yaml
oc apply -f day-7/manifests/bbr-qwen-httproute.yaml
```

Re-run [day-7/run-day7-install.sh](day-7/run-day7-install.sh) to refresh subscription, OLSConfig, and MaaS API key.

### Validate

```bash
source day-7/lightspeed-maas.env
curl -s -o /dev/null -w "plain: HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${LIGHTSPEED_MAAS_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-4b-instruct","messages":[{"role":"user","content":"ping"}],"max_tokens":5}'
curl -s -o /dev/null -w "tool_choice auto: HTTP %{http_code}\n" -X POST "${MAAS_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${LIGHTSPEED_MAAS_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-4b-instruct","messages":[{"role":"user","content":"ping"}],"max_tokens":10,"tool_choice":"auto","tools":[{"type":"function","function":{"name":"noop","description":"No-op","parameters":{"type":"object","properties":{}}}}]}'
```

Both should return **HTTP 200**. Then retry the Lightspeed console.

See [day-7/CHANGES.md](day-7/CHANGES.md) section 9.

---

If a live scenario fails during client presentation:

| Scenario | Fallback |
|----------|----------|
| Gateway routing | [AI Gateway Flow animation](https://noyitz.github.io/ai-gateway-docs/ai-gateway-flow.html) |
| MaaS features overview | [Official MaaS video](https://drive.google.com/file/d/17pLFqDMEi2-XjxsWp70saDPyb_IHHoHf/view) |
| Model signing | [RHTAS demo video](https://drive.google.com/file/d/1eZq40RzaphljAHk4LcIWGZOs654xLcvQ/view) |
| Guardrails | Pre-captured `status: blocked` output from Day 4 validation |
| Lightspeed UI | Direct MaaS probe — see [day-7/README.md](day-7/README.md) fallback curl |

---

## Related Documents

- [03-cluster-validation-commands.md](03-cluster-validation-commands.md)
- [04-installation-and-ready-state.md](04-installation-and-ready-state.md)
- [05-demonstration-steps.md](05-demonstration-steps.md)
