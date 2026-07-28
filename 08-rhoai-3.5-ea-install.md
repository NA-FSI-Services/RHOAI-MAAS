# RHOAI 3.5 Early Access (EA) — MaaS Install Notes

Branch: `rhoai-3.5-ea`  
Target CSV: `rhods-operator.3.5.0-ea.2`  
Channel: `beta`  
Cluster baseline: OpenShift 4.20.x with 3× `g6.4xlarge` (NVIDIA L4) GPU workers

This supersedes the RHOAI **3.4** / `stable-3.x` path in [04-installation-and-ready-state.md](04-installation-and-ready-state.md) for Early Access clusters. Upstream PoC guide (`rhoai-maas-guide`) still documents 3.4 `kserve.modelsAsService`; **3.5-ea moves MaaS under the AI Gateway component**.

---

## Cluster state (fresh sandbox)

| Check | Expected |
|-------|----------|
| `oc get clusterversion` | 4.20.x Available |
| GPU MachineSet | 3 ready GPU workers |
| Operators before MaaS | cert-manager, NFD, NVIDIA GPU Operator, RHCL, LWS, RHOAI |
| GPU allocatable | `nvidia.com/gpu=1` on each GPU node |

Verify GPUs after NFD + ClusterPolicy reconcile (~5–15 min):

```bash
oc get nodes "-o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu" | grep -v '<none>'
```

---

## Critical 3.5-ea API notes (MaaS)

| Topic | RHOAI 3.4 | RHOAI 3.5.0-ea.2 (this cluster) |
|-------|-----------|----------------------------------|
| Enable MaaS | `kserve.modelsAsService: Managed` | **Still** `kserve.modelsAsService: Managed` on the installed CRD |
| AI Gateway | N/A / embedded | Also set `aigateway.managementState: Managed` (new v2 component) |
| Upstream docs | kserve path | Docs may show `aigateway.modelsAsAService` — **not present** on EA2 CRD yet; keep `kserve.modelsAsService` until the field appears |
| Guide DSC | `manifests/04-rhoai-config/datasciencecluster.yaml` | Prefer [day-2/manifests/datasciencecluster-3.5-ea.yaml](day-2/manifests/datasciencecluster-3.5-ea.yaml) |
| Gateway | Create `maas-default-gateway` | Still required for MaaS samples; RHOAI also auto-creates `data-science-gateway` via `GatewayConfig/default-gateway` |
| Gateway ConfigMap | `maas-gateway-options` | **Required** (`manifests/02-platform-config/gateway-resources.yaml`) or Programmed stays False |
| Public hostname | Route / DNS | Apply [day-2/manifests/maas-gateway-route.yaml.tmpl](day-2/manifests/maas-gateway-route.yaml.tmpl) (passthrough → gateway Service) |
| Subscriptions | shared `priority: 10` OK in 3.4 samples | EA2 enforces unique `spec.priority` (`SharedPriority`) |

Canonical upstream reference: [opendatahub-io/models-as-a-service — maas-setup](https://github.com/opendatahub-io/models-as-a-service/blob/main/docs/content/install/maas-setup.md)

**Install order (do not invert):**

1. Operators (RHCL + RHOAI CSV Succeeded)
2. Kuadrant / Authorino TLS + `maas-default-gateway` **Programmed**
3. PostgreSQL + `maas-db-config` secret (infra / applications namespace)
4. Enable DSC `aigateway` + `modelsAsAService: Managed` (plus `kserve` if you serve models)
5. Dashboard flags (`genAiStudio`, `modelAsService` / UI equivalents)
6. Deploy models (`LLMInferenceService` → `MaaSModelRef` → subscription + auth policy)

---

## Operator install

### RHOAI OperatorGroup

Must **not** set `spec.targetNamespaces` (AllNamespaces). OwnNamespace fails with:

`UnsupportedOperatorGroup: OwnNamespace InstallModeType not supported`

```bash
oc apply -f work/rhoai-maas-guide/manifests/01-prerequisites/operators/rhoai-operator/operatorgroup.yaml
```

### Subscription (beta / EA2)

```bash
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: beta
  installPlanApproval: Automatic
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: rhods-operator.3.5.0-ea.2
EOF

oc wait csv/rhods-operator.3.5.0-ea.2 -n redhat-ods-operator \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s
```

### Companion operators

```bash
# Already present or apply from guide (RHCL Automatic — do not pin Manual 1.3.4 on fresh 1.4 catalogs)
oc apply -k work/rhoai-maas-guide/manifests/01-prerequisites/operators/cert-manager/
oc apply -k work/rhoai-maas-guide/manifests/01-prerequisites/operators/leader-worker-set/

# RHCL — prefer Automatic / latest stable (v1.4.x)
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhcl-operator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: rhcl-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

NFD + NVIDIA GPU Operator (required before GPU models schedule):

```bash
# See day-1/run-day1-gpu-operators.sh (NFD instance + ClusterPolicy)
./day-1/run-day1-gpu-operators.sh
```

---

## Platform + MaaS enablement

Follow guide phases 2–3, then apply the **3.5-ea DSC**:

```bash
GUIDE=work/rhoai-maas-guide

# Phase 2 — Kuadrant, UWM, GatewayClass, gateway (from day-1 script or guide)
./day-1/run-day1-install.sh   # skip GPU MachineSet names that do not match this cluster

# Phase 3 — Postgres + maas-db-config
oc apply -k "$GUIDE/manifests/03-maas-platform/"
# Ensure Authorino TLS (guide setup-maas.sh / day-2)

# Phase 4 — RHOAI 3.5-ea DSC (aigateway.modelsAsAService)
oc apply -f day-2/manifests/dscinitialization.yaml   # or guide DSCI if compatible
oc wait --for=jsonpath='{.status.phase}'=Ready dscinitialization/default-dsci --timeout=600s
oc apply -f day-2/manifests/datasciencecluster-3.5-ea.yaml
oc wait --for=jsonpath='{.status.phase}'=Ready datasciencecluster/default-dsc --timeout=900s
```

Verify MaaS:

```bash
oc get datasciencecluster default-dsc -o yaml | grep -A6 aigateway
oc get deployment -A | grep -iE 'maas-api|maas-controller|ai-gateway'
oc get crd | grep -iE 'maas|aitenant|aigateway'
```

---

## Models on this branch

Sized for **1× L4 (24 GB)** each:

| Model | LLMInferenceService | ModelCar / URI |
|-------|---------------------|----------------|
| Llama 3.1 8B Instruct FP8 | `llama-3-1-8b-instruct` | `oci://registry.redhat.io/rhelai1/modelcar-llama-3-1-8b-instruct-fp8-dynamic:1.5` |
| Gemma 4 E4B Instruct | `gemma-4-e4b-it` | `hf://google/gemma-4-E4B-it` (Apache-2.0; no RH ModelCar for E4B on L4 yet) |

Manifests: [day-2/manifests/models/](day-2/manifests/models/)

```bash
oc create namespace llm --dry-run=client -o yaml | oc apply -f -
oc apply -k day-2/manifests/models/llama-3-1-8b-instruct/
oc apply -k day-2/manifests/models/gemma-4-e4b-it/
```

> **Gemma 4 note:** Validated RH ModelCars for Gemma 4 (26B/31B FP8) need ~33–39 GB VRAM (H200-class). On L4 use the Hugging Face E4B IT checkpoint (`hf://google/gemma-4-E4B-it`). The GA `rhaiis/vllm-cuda-rhel9:3.3.0` image does **not** recognize `gemma4` — use the RHOAI 3.5 EA relatedImage `registry.redhat.io/rhaii-early-access/vllm-cuda-rhel9@sha256:…` from the CSV. If the HF pull requires a token, see `CONFIGURATION.md`.

---

## EA caveats

- EA builds are **unsupported**; upgrades EA→GA need a fresh install.
- Guide `setup-maas.sh` may still emit 3.4 DSC fields — prefer the manifests in this branch.
- Authorino namespace may be `kuadrant-system` or `rh-connectivity-link` depending on RHCL version; set `AUTHORINO_NAMESPACE` accordingly when using upstream TLS scripts.
- Do not grant retail personas Granite via `system:authenticated` catch-alls — see Day 6 lockdown patterns if you re-add Granite later.

---

## Validation quick checks

```bash
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
export MAAS_URL="https://maas.${CLUSTER_DOMAIN}"

oc get csv -n redhat-ods-operator
oc get datasciencecluster default-dsc
oc get llminferenceservice,maasmodelref -n llm
curl -sk "${MAAS_URL}/maas-api/health"
```

See also [03-cluster-validation-commands.md](03-cluster-validation-commands.md) and [AGENTS.md](AGENTS.md).
