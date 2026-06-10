# Day 1 Installation — Change Log and Deviations

**Date:** 2026-06-05  
**Script:** [run-day1-install.sh](run-day1-install.sh)  
**Guide repo:** [../work/rhoai-maas-guide](../work/rhoai-maas-guide)

This document records conflicts between the original PoC plan and the live cluster, and how they were resolved during Day 1.

---

## 1. Repository layout (plan vs guide)

| Original plan | Actual guide (2026) | Resolution |
|---------------|-------------------|------------|
| `01-prerequisites/operators/` at repo root | `manifests/01-prerequisites/operators/` | Updated paths in runbook and Day 1 script |
| Standalone `./scripts/setup-gateway.sh` | Gateway rendered via `setup-maas.sh` Phase 2 / `gateway.yaml.tmpl` | Day 1 uses `envsubst` + template from `manifests/02-platform-config/` |
| `granite-3-8b-instruct` (2 replicas, HF pull) | `granite-tiny-gpu` (`granite-4-tiny`, 1 replica, OCI modelcar) | Deferred to Day 2; see updated model table in [04-installation-and-ready-state.md](../04-installation-and-ready-state.md) |
| Manual 3-day phase split | `setup-maas.sh` phases 0–7 (Phase 3=RHOAI, Phase 4=MaaS platform) | Day 1 runs phases 1–2 only via custom script; Day 2 should use `setup-maas.sh --from-phase 3` |

---

## 2. GPU infrastructure

| Original plan | Actual cluster | Resolution |
|---------------|----------------|------------|
| 3× `g6.4xlarge` (L4) via RHDP catalog | MachineSets use **`g6e.2xlarge`** | Scaled existing `worker-gpu-big` MachineSets in zones 2b and 2c to 1 replica each |
| Manual RHDP provisioning | `oc patch machineset … --type=merge -p '{"spec":{"replicas":1}}'` | **Success:** 3 GPU nodes in ~10 minutes |

**GPU nodes after Day 1:**

| Node | Instance | GPUs |
|------|----------|------|
| ip-10-0-20-178 | g6e.2xlarge | 1 |
| ip-10-0-40-203 | g6e.2xlarge | 1 |
| ip-10-0-85-158 | g6e.2xlarge | 1 |

**Impact on demo plan:** NeMo Guardrails + 2 Granite replicas remain feasible on 3 GPUs; use `granite-tiny-gpu` (single replica) or 2 replicas only if VRAM allows on g6e (L40S-class 48GB — sufficient for tiny Granite).

---

## 3. RHOAI operator conflict (critical)

**Problem:** Applying `manifests/01-prerequisites/operators/` created a **duplicate OperatorGroup** (`redhat-ods-operator`) in namespace `redhat-ods-operator`, alongside the existing GitOps-managed `rhods-operator` OperatorGroup. OLM error:

```
csv created in namespace with multiple operatorgroups, can't pick one automatically
```

This caused `rhods-operator.3.4.0` CSV to show **Failed** cluster-wide.

**Remediation:**

```bash
oc delete operatorgroup redhat-ods-operator -n redhat-ods-operator
# Keep existing OperatorGroup: rhods-operator
```

**Result:** CSV returned to **Succeeded** within ~30 seconds. DSC remained **Ready**.

**Day 2 guidance:** On GitOps-managed clusters, **skip** re-applying `manifests/01-prerequisites/operators/rhoai-operator/` or apply only cert-manager + LWS subdirectories:

```bash
oc apply -k manifests/01-prerequisites/operators/cert-manager/
oc apply -k manifests/01-prerequisites/operators/connectivity-link/
oc apply -k manifests/01-prerequisites/operators/service-mesh/
oc apply -k manifests/01-prerequisites/operators/leader-worker-set/
```

---

## 4. Operators installed / verified

| Operator | Namespace | Status after Day 1 |
|----------|-----------|-------------------|
| rhods-operator 3.4.0 | redhat-ods-operator | Succeeded (after OG cleanup) |
| rhcl-operator 1.3.4 | openshift-operators | Succeeded |
| servicemeshoperator3 3.1.0 | openshift-operators | Succeeded |
| authorino-operator 1.3.1 | openshift-operators | Succeeded |
| limitador-operator 1.3.1 | openshift-operators | Succeeded |
| cert-manager-operator 1.19.0 | cert-manager-operator | **New** — Succeeded |
| leader-worker-set 1.0.0 | openshift-lws-operator | **New** — Succeeded |

---

## 5. Platform configuration (Phase 2)

| Step | Result |
|------|--------|
| Kuadrant Ready | Already existed; verified Ready |
| User Workload Monitoring | Already enabled; skipped |
| GatewayClass `openshift-default` | Already existed; skipped |
| Gateway `maas-default-gateway` Programmed | Verified |
| Authorino TLS bootstrap annotation | **Applied** (`security.opendatahub.io/authorino-tls-bootstrap=true`) |
| Authorino serving cert (`service-annotation.yaml`) | **Not applied Day 1** — caused Day 2/3 gateway HTTP 500 until fixed in Day 3 |

---

## 6. Day 1 exit criteria scorecard

| Criterion | Target | Result |
|-----------|--------|--------|
| 3 allocatable GPUs | 3 | **Pass** |
| Kuadrant Ready | Ready | **Pass** |
| maas-default-gateway Programmed | True | **Pass** |
| MaaS dependency CSVs Succeeded | All | **Pass** (after rhods OG fix) |
| modelsAsService Managed | — | **Not in Day 1 scope** (Day 2) |
| PostgreSQL / governance CRs | — | **Not in Day 1 scope** (Day 2) |

---

## 7. Files updated in PoC package

| File | Change |
|------|--------|
| [04-installation-and-ready-state.md](../04-installation-and-ready-state.md) | Corrected paths, GPU scaling via MachineSet, GitOps operator caveat, model names |
| [01-engineering-blueprint.md](../01-engineering-blueprint.md) | Added guide model table reference |
| [run-day1-install.sh](run-day1-install.sh) | Should skip rhoai-operator on GitOps clusters (see note below) |

---

## 8. Recommended script change for Day 2+

Before re-running operator phase on this cluster, patch `run-day1-install.sh` or use selective apply to avoid duplicate OperatorGroup. The cluster is GitOps-managed (ArgoCD annotations on DSC); prefer:

```bash
./scripts/setup-maas.sh --from-phase 3 --skip-models --skip-verify
```

for Day 2 MaaS activation instead of manual DSC patches.

---

## 9. Multi-user htpasswd IdP (2026-06-07)

**Goal:** Distinct `user` labels in MaaS observability metrics (not all `admin`).

| Component | Location |
|-----------|----------|
| htpasswd IdP + secret | [setup-multi-user.sh](setup-multi-user.sh) |
| Persona groups | [manifests/demo-groups.yaml](manifests/demo-groups.yaml) |
| RHOAI project setup (playground) | [../07-ui-based-demonstration-steps.md](../07-ui-based-demonstration-steps.md#step-01--create-rhoai-projects-before-playground) |
| Password template | [demo-users-passwords.env.example](demo-users-passwords.env.example) |
| Full guide | [../MULTI-USER-ACCESS.md](../MULTI-USER-ACCESS.md) |
| Playground troubleshooting | [../06-troubleshooting.md](../06-troubleshooting.md#gen-ai-playground--configmap-forbidden-wrong-project) |

Adds identity provider `maas-demo-users` **alongside** existing `rhbk` OpenID — no IdP removal.

Users: `demo-retail-analyst`, `demo-risk-analyst`, `demo-platform-ops`  
Groups: `maas-demo-retail-analyst`, `maas-demo-risk-analytics`, `maas-demo-platform-ops`

**Gen AI playground:** Each persona creates a **dedicated RHOAI project** (namespace admin) before **Try in playground** — see [07-ui-based-demonstration-steps.md](../07-ui-based-demonstration-steps.md#step-01--create-rhoai-projects-before-playground). Do **not** grant RBAC on shared namespaces such as `grafana`.
