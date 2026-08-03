# Day 6 Installation — Change Log and Deviations

**Date:** 2026-06-05  
**Script:** [run-day6-install.sh](run-day6-install.sh)

---

## 1. Observability was UI-only until Day 6

| Original plan (Days 1–3) | Actual before Day 6 | Day 6 resolution |
|--------------------------|---------------------|----------------|
| Enable `observabilityDashboard: true` | Flag set; **COO not installed** | Installed Cluster Observability Operator (Phase 7) |
| Perses MaaS usage dashboard | CRDs/dashboard missing | `dashboard-3-maas-usage-admin` appeared after COO |

**Root cause:** Day 3 only patched `OdhDashboardConfig`. The Observability tab requires COO + **RHOAI observability stack** (DSCInitialization `metrics.storage`, OpenTelemetry operator, Perses backend) + gateway telemetry. See [OBSERVABILITY-TROUBLESHOOTING.md](OBSERVABILITY-TROUBLESHOOTING.md).

---

## 2. Per-user showback requires dedicated subscriptions + keys

| Blueprint assumption | Sandbox reality | Resolution |
|---------------------|-----------------|------------|
| Named OpenShift groups (`basic-users-group`) | Admin-only cluster | **Subscription-scoped API keys** as demo “users” |
| Single basic/advanced key pair | Insufficient for multi-user charts | Three persona subscriptions + keys |

Telemetry labels (`user`, `subscription`, `cost_center`, `organization_id`) come from Authorino identity + `tokenMetadata` on subscriptions.

---

## 3. Demo personas, rate limits, and metadata

| Persona | Subscription | TPM limits (per model) | Org / Cost center |
|---------|--------------|------------------------|-------------------|
| Retail Analyst | `demo-retail-analyst` | 3,000/min (simulator + external) | `org-retail` / `CC-RETAIL-1001` |
| Risk Analytics | `demo-risk-analytics` | 80,000/min Granite; 20,000/min external | `org-risk` / `CC-RISK-2001` |
| Platform Engineering | `demo-platform-ops` | 10k sim, 25k Granite, 10k external | `org-platform` / `CC-PLATFORM-3001` |

Legacy Day 3 keys (`simulator-free`, `granite-tiny-gpu-premium`) remain valid for auth demos; **use Day 6 keys for Observability demo**.

---

## 4. Enhanced telemetry policy

GitOps deployed `TelemetryPolicy/user-group` (model, tier, user). Day 6 adds `maas-telemetry` with showback labels:

- `subscription`
- `organization_id`
- `cost_center`

Both policies target `maas-default-gateway` and reconcile successfully.

---

## 5. Daily traffic cadence until demo day

| When | Action |
|------|--------|
| Day 6 (install) | `./run-day6-install.sh` then `./daily-traffic.sh` |
| Daily until demo | `./daily-traffic.sh` (~09:00 local) |
| Demo morning | `./daily-traffic.sh --quick` (~30 min before presenting) |

Optional cron (from machine with `oc` + keys):

```cron
0 9 * * * /path/to/PoC/day-6/daily-traffic.sh --cron
```

---

## 6. Day 6 exit criteria

| Criterion | Result |
|-----------|--------|
| COO CSV Succeeded | **Pass** |
| Perses MaaS dashboard exists | **Pass** |
| Demo subscriptions Active | **Pass** |
| Per-persona API keys minted | **Pass** → `demo-users.env` |
| Daily traffic script HTTP 200 | **Pass** |
| Observability UI shows data | **Verify manually** in RHOAI Console |

---

## 8. Observability backend gaps (fixed 2026-06-05)

| Gap | Resolution |
|-----|------------|
| DSCI `metrics.storage` empty → no Perses pod | [manifests/dsci-metrics-storage.yaml](manifests/dsci-metrics-storage.yaml) |
| OpenTelemetry operator not installed | [manifests/opentelemetry-operator/subscription.yaml](manifests/opentelemetry-operator/subscription.yaml) |
| Missing `kuadrant-prometheus-datasource-secret` | [fix-perses-datasource-secret.sh](fix-perses-datasource-secret.sh) |

Documented in [OBSERVABILITY-TROUBLESHOOTING.md](OBSERVABILITY-TROUBLESHOOTING.md).

---

## 7. Files updated in PoC package

| File | Change |
|------|--------|
| [05-demonstration-steps.md](../05-demonstration-steps.md) | Demo 6 users table + traffic steps |
| [04-installation-and-ready-state.md](../04-installation-and-ready-state.md) | Day 6 section |
| [02-cluster-current-state.md](../02-cluster-current-state.md) | COO + personas |
| [scripts/seed-demo-traffic.sh](../scripts/seed-demo-traffic.sh) | Legacy seed (Day 3 keys); prefer `daily-traffic.sh` |

---

## 8. Advanced Guardrails bindings

`run-day6-install.sh` applies [manifests/demo-guardrail-bindings.yaml](manifests/demo-guardrail-bindings.yaml) when present (maps persona orgs/groups to Day 4 policy packs). See [09-advanced-guardrails-plan.md](../09-advanced-guardrails-plan.md).
