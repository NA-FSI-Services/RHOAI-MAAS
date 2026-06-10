# Observability Dashboard Troubleshooting (Day 6)

**Symptom:** RHOAI Console → **Observe & monitor → Dashboard** shows:

```text
Error loading components
Service Unavailable
```

**URL example:** `https://rh-ai.apps.<cluster>/observe-and-monitor/dashboard`

---

## Root cause (2026-06-05)

Day 6 originally installed **COO + gateway telemetry + PersesDashboard CRs** but **did not enable the RHOAI observability backend**. Three gaps blocked the UI:

| Gap | Symptom in cluster | Fix |
|-----|-------------------|-----|
| **1. DSCI metrics storage empty** | `Monitoring` CR: `PersesAvailable=False`, `MetricsNotConfigured`; `redhat-ods-monitoring` namespace empty | Apply [manifests/dsci-metrics-storage.yaml](manifests/dsci-metrics-storage.yaml) |
| **2. OpenTelemetry operator missing** | `Monitoring` CR: `OpenTelemetryCollector operator must be installed` | Apply [manifests/opentelemetry-operator/subscription.yaml](manifests/opentelemetry-operator/subscription.yaml) |
| **3. Perses datasource secret missing** | `PersesDatasource/kuadrant-prometheus-datasource` stuck; no `kuadrant-prometheus-datasource-secret` | Run [fix-perses-datasource-secret.sh](fix-perses-datasource-secret.sh) |

Enabling only `observabilityDashboard: true` on `OdhDashboardConfig` is **not sufficient** — the Perses **server** must be running in `redhat-ods-monitoring`.

---

## Fix procedure (cluster)

Run the updated Day 6 installer (applies all three fixes):

```bash
cd PoC/day-6
./run-day6-install.sh
```

Or apply manually:

```bash


# 1. RHOAI observability stack (Perses + Prometheus + Thanos)
oc apply -f day-6/manifests/dsci-metrics-storage.yaml
oc apply -f day-6/manifests/opentelemetry-operator/subscription.yaml

# Wait for OpenTelemetry CSV Succeeded, then for monitoring pods (~2–5 min)
oc get csv -n openshift-opentelemetry-operator
oc get pods -n redhat-ods-monitoring

# 2. Perses datasource auth secret
./day-6/fix-perses-datasource-secret.sh

# 3. Seed traffic so charts have data
./day-6/daily-traffic.sh --quick
```

---

## Verification checklist

### A. RHOAI monitoring stack

```bash
oc get monitoring default-monitoring -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}' | grep -E 'Ready|Perses|MonitoringStack'
oc get pods -n redhat-ods-monitoring
```

**Expected pods (subset):**

- `data-science-perses-0` — **Running**
- `prometheus-data-science-monitoringstack-0` — **Running**
- `thanos-querier-data-science-thanos-querier-*` — **Running**

### B. MaaS Perses objects

```bash
oc get persesdashboard dashboard-3-maas-usage-admin -n redhat-ods-applications
oc get persesdatasource kuadrant-prometheus-datasource -n redhat-ods-applications
oc get secret kuadrant-prometheus-datasource-secret -n redhat-ods-applications
```

**Expected:** Dashboard and datasource `Available=True`; secret exists.

### C. Kuadrant metrics in platform Prometheus

```bash
TOKEN=$(oc whoami -t)
curl -sk -G -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'query=authorized_hits{subscription!=""}' \
  "https://thanos-querier-openshift-monitoring.apps.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')/api/v1/query" \
  | jq '.data.result | length'
```

**Expected:** `> 0` after running `./daily-traffic.sh`.

### D. RHOAI Console UI

1. Hard-refresh the browser (or open a private window).
2. Open **Observe & monitor → Dashboard (Tech Preview)**.
3. Select **MaaS usage** (`dashboard-3-maas-usage-admin`).
4. Group/filter by **user**, **subscription**, or **cost_center**.

---

## Viewing metrics outside the RHOAI Console

The **MaaS usage Perses dashboard** is integrated into the **RHOAI AI Console** (`rh-ai` route). It is **not** automatically mirrored to the OpenShift Administrator console in this PoC.

### Option 1 — OpenShift Console → Observe → Metrics (platform)

For ad-hoc PromQL on **Kuadrant/Limitador** metrics (same source as the MaaS dashboard):

1. Open **OpenShift Console** (Administrator).
2. Go to **Observe → Metrics**.
3. Run queries such as:

```promql
authorized_hits{subscription!=""}
authorized_hits{subscription="demo-risk-analytics"}
```

Requires cluster-monitoring-view (cluster-admin has this).

### Option 2 — RHOAI Prometheus / Thanos routes

Routes in `redhat-ods-monitoring` (Networking → Routes):

| Route | Use |
|-------|-----|
| `data-science-prometheus-route` | RHOAI MonitoringStack Prometheus UI |
| `data-science-thanos-querier-route` | RHOAI Thanos querier (DS workloads) |
| `data-science-prometheus-cluster-proxy` | Cluster-scoped proxy |

These cover the **RHOAI observability stack**, not the Kuadrant `authorized_hits` series used for MaaS showback (those live in **platform** Thanos with UWM).

### Option 3 — Platform Thanos (CLI)

```bash
TOKEN=$(oc whoami -t)
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
curl -sk -H "Authorization: Bearer $TOKEN" \
  -G --data-urlencode 'query=authorized_hits' \
  "https://thanos-querier-openshift-monitoring.apps.${CLUSTER_DOMAIN}/api/v1/query"
```

### OpenShift Console Perses UIPlugin (not configured)

Cluster Observability Operator 1.4 can expose **Perses** in the OpenShift Console via a `UIPlugin` CR. This PoC uses **RHOAI-managed** `PersesDashboard` CRs (`dashboard-3-maas-usage-admin`) wired to the RHOAI dashboard — a separate integration path. To use OCP-native Perses dashboards you would import/create dashboards under COO’s UIPlugin model (Technology Preview, additional setup).

**Recommendation for demo:** Use **RHOAI Console → Observe & monitor** (Demo 6 script). Use **OpenShift Observe → Metrics** only as a fallback for raw PromQL.

---

## Ongoing demo prep

```bash
./day-6/daily-traffic.sh          # daily until demo
./day-6/daily-traffic.sh --quick # demo morning
```

Rotate the datasource token if the secret expires (default 8760h):

```bash
./day-6/fix-perses-datasource-secret.sh
```

---

## Changes applied to PoC docs/scripts

| File | Change |
|------|--------|
| [run-day6-install.sh](run-day6-install.sh) | DSCI metrics + OpenTelemetry + datasource secret + stack wait |
| [manifests/dsci-metrics-storage.yaml](manifests/dsci-metrics-storage.yaml) | Enable RHOAI MonitoringStack/Perses |
| [manifests/opentelemetry-operator/subscription.yaml](manifests/opentelemetry-operator/subscription.yaml) | OpenTelemetry operator prerequisite |
| [manifests/perses-thanos-reader-rbac.yaml](manifests/perses-thanos-reader-rbac.yaml) | SA for Thanos queries |
| [fix-perses-datasource-secret.sh](fix-perses-datasource-secret.sh) | Create datasource secret |
| [README.md](README.md), [CHANGES.md](CHANGES.md) | Updated prerequisites |
| [../06-troubleshooting.md](../06-troubleshooting.md) | Link + summary |
| [../05-demonstration-steps.md](../05-demonstration-steps.md) | Demo 6 verify + fallback paths |

---

## Related

- [README.md](README.md) — Day 6 install and personas
- [Red Hat RHOAI 3.4 — Managing observability](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai/managing-observability_managing-rhoai)
- [rhoai-maas-guide Phase 7](../work/rhoai-maas-guide/manifests/07-observability/)
