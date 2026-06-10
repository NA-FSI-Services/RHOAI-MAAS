# Day 6 Installation Results

**Completed:** 2026-06-05  
**Focus:** Cluster Observability Operator (COO), governance metadata, per-user demo traffic

---

## Summary

Day 6 enables the **Observability & showback** dashboard (Technology Preview) and seeds **three demo personas** with distinct subscriptions, token rate limits, and cost-center metadata for rich per-user charts on demo day.

| Criterion | Result |
|-----------|--------|
| COO installed | **Pass** — `cluster-observability-operator.v1.4.0` Succeeded |
| RHOAI Perses backend | **Pass** — `data-science-perses` in `redhat-ods-monitoring` |
| OpenTelemetry operator | **Pass** — prerequisite for RHOAI monitoring stack |
| Perses MaaS dashboard | **Pass** — `dashboard-3-maas-usage-admin` |
| Kuadrant datasource secret | **Pass** — `kuadrant-prometheus-datasource-secret` |
| Enhanced telemetry | **Pass** — `maas-telemetry` Enforced |
| Demo subscriptions | **Pass** — 3 Active |
| Per-user API keys | **Pass** — see `demo-users.env` (local); minted via [mint-persona-keys.sh](mint-persona-keys.sh) as htpasswd users |
| Daily traffic | **Pass** — all personas HTTP 200 |

---

## Install

```bash
cd PoC/day-6
chmod +x run-day6-install.sh daily-traffic.sh
./run-day6-install.sh
```

Creates `demo-users.env` with three API keys (gitignored). Requires [day-1/setup-multi-user.sh](../day-1/setup-multi-user.sh) for distinct user metrics — see [MULTI-USER-ACCESS.md](../MULTI-USER-ACCESS.md).

---

## Demo users and rate limits

These personas appear as separate **users** in the Observability dashboard when keys are minted per htpasswd user ([MULTI-USER-ACCESS.md](../MULTI-USER-ACCESS.md)).

| Persona | API key env var | Subscription | Models | Token rate limit (per model) | Showback metadata |
|---------|-----------------|--------------|--------|----------------------------|-------------------|
| **Retail Analyst** | `DEMO_RETAIL_KEY` | `demo-retail-analyst` | Simulator, external CodeLlama | **3,000 / min** | Org: `org-retail`, CC: `CC-RETAIL-1001` |
| **Risk Analytics** | `DEMO_RISK_KEY` | `demo-risk-analytics` | Granite, external CodeLlama | **80,000 / min** Granite; **20,000 / min** external | Org: `org-risk`, CC: `CC-RISK-2001` |
| **Platform Engineering** | `DEMO_PLATFORM_KEY` | `demo-platform-ops` | All three models | **10k / 25k / 10k** per min | Org: `org-platform`, CC: `CC-PLATFORM-3001` |

### Legacy keys (still used for auth demos 2–3)

| Key | Subscription | Purpose |
|-----|--------------|---------|
| `BASIC_USER_KEY` | `simulator-free` | 401/403/429 demos |
| `ADVANCED_USER_KEY` | `granite-tiny-gpu-premium` | Granite entitlement demo |

---

## Daily traffic until demo day

Run **once per day** after Day 6 to build time-series data:

```bash
source day-3/demo-env.sh   # optional; daily-traffic sources both env files
./day-6/daily-traffic.sh
```

| Schedule | Command | Purpose |
|----------|---------|---------|
| Daily (~09:00) | `./daily-traffic.sh` | Full seed — 3 loops × 3 personas |
| Demo morning | `./daily-traffic.sh --quick` | Fresh “last hour” activity |
| Unattended | `./daily-traffic.sh --cron` | Append results to `~/maas-demo-traffic.log` |

Example cron (adjust path):

```cron
0 9 * * * cd /path/to/PoC && ./day-6/daily-traffic.sh --cron
```

Each persona generates a **different traffic profile**:

- **Retail** — low-volume simulator + external (flat TPM line)
- **Risk** — token-heavy Granite requests (spikes TPM chart)
- **Platform** — balanced cross-model calls (multi-series dashboard)

---

## Verify observability

1. **RHOAI Console** → **Observe & monitor** → **Dashboard (Tech Preview)**
2. Dashboard: **MaaS usage** (`dashboard-3-maas-usage-admin`)
3. Filter/group by **user**, **subscription**, **cost_center**, or **model**
4. **Export CSV** for showback slide

If you see **Service Unavailable**, see [OBSERVABILITY-TROUBLESHOOTING.md](OBSERVABILITY-TROUBLESHOOTING.md).

### Fallback: OpenShift Console metrics (same Kuadrant data)

Administrator → **Observe → Metrics** → query `authorized_hits{subscription!=""}` (see troubleshooting doc).

---

## File index

| File | Description |
|------|-------------|
| [CHANGES.md](CHANGES.md) | Plan deviations |
| [run-day6-install.sh](run-day6-install.sh) | COO + personas + initial seed |
| [daily-traffic.sh](daily-traffic.sh) | Repeatable daily traffic |
| [mint-persona-keys.sh](mint-persona-keys.sh) | Mint keys as each htpasswd user |
| [manifests/demo-maas-api-rbac.yaml](manifests/demo-maas-api-rbac.yaml) | RBAC for per-user key minting |
| [manifests/demo-subscriptions.yaml](manifests/demo-subscriptions.yaml) | Subscriptions + TPM + metadata |
| [manifests/demo-auth-policies.yaml](manifests/demo-auth-policies.yaml) | Auth policies |
| [OBSERVABILITY-TROUBLESHOOTING.md](OBSERVABILITY-TROUBLESHOOTING.md) | Service Unavailable fix + OCP console fallbacks |
| [fix-perses-datasource-secret.sh](fix-perses-datasource-secret.sh) | Refresh Thanos auth secret for Perses |
| [manifests/dsci-metrics-storage.yaml](manifests/dsci-metrics-storage.yaml) | Enable RHOAI MonitoringStack + Perses |
| [manifests/opentelemetry-operator/subscription.yaml](manifests/opentelemetry-operator/subscription.yaml) | OpenTelemetry operator |
| [05-validation.txt](05-validation.txt) | Post-install validation |

---

## Governance notes

- **Rate limits** are enforced by Kuadrant `TokenRateLimitPolicy` per subscription/model (see subscription YAML).
- **Cost attribution** uses `spec.tokenMetadata` on `MaaSSubscription` — surfaced in telemetry as `organization_id` and `cost_center`.
- **User identity** in metrics maps to the API key / Authorino `userid` — one key per persona keeps dashboard series distinct.
