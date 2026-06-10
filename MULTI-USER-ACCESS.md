# Multi-User Access for MaaS Observability

This guide configures **three distinct htpasswd users** with persona-specific OpenShift groups, MaaS subscriptions, and API keys so the observability dashboard shows separate **user** labels (not all `admin`).

## Why

Kuadrant telemetry policy labels metrics with `user: auth.identity.userid`. When cluster-admin mints all API keys, every hit appears as user `admin`. Per-user key minting (each user logs in with htpasswd and calls `POST /maas-api/v1/api-keys`) attributes traffic to `demo-retail-analyst`, `demo-risk-analyst`, and `demo-platform-ops`.

## Personas

| Persona | htpasswd user | OpenShift group | Subscription | Models |
|---------|---------------|-----------------|--------------|--------|
| Retail Analyst | `demo-retail-analyst` | `maas-demo-retail-analyst` | `demo-retail-analyst` | simulator, codellama |
| Risk Analytics | `demo-risk-analyst` | `maas-demo-risk-analytics` | `demo-risk-analytics` | granite, codellama |
| Platform Ops | `demo-platform-ops` | `maas-demo-platform-ops` | `demo-platform-ops` | all three |

Default passwords (PoC demo only — see [day-1/demo-users-passwords.env.example](day-1/demo-users-passwords.env.example); copy to gitignored `demo-users-passwords.env`):

The existing **rhbk** OpenID IdP is preserved; htpasswd is added alongside it.

---

## Quick setup (existing cluster)

```bash
cd PoC

# 1. Passwords (gitignored)
cp day-1/demo-users-passwords.env.example day-1/demo-users-passwords.env

# 2. htpasswd IdP + groups
chmod +x day-1/setup-multi-user.sh
./day-1/setup-multi-user.sh

# 3. Persona subscriptions, auth policies, RBAC
oc apply -f day-6/manifests/demo-subscriptions.yaml
oc apply -f day-6/manifests/demo-auth-policies.yaml
oc apply -f day-6/manifests/demo-restrict-default-granite.yaml
oc delete maassubscription granite-tiny-gpu-free -n models-as-a-service --ignore-not-found
oc apply -f day-6/manifests/demo-maas-api-rbac.yaml

# 4. Mint keys as each user (not admin)
chmod +x day-6/mint-persona-keys.sh
./day-6/mint-persona-keys.sh

# 5. Seed metrics
./day-6/daily-traffic.sh --quick
```

---

## Step-by-step

### 1. htpasswd identity provider (Day 1)

Files:

- [day-1/setup-multi-user.sh](day-1/setup-multi-user.sh) — creates secret, patches OAuth, applies groups
- [day-1/manifests/demo-groups.yaml](day-1/manifests/demo-groups.yaml) — Group CRs
- [day-1/demo-users-passwords.env.example](day-1/demo-users-passwords.env.example) — password template

The script:

1. Builds an htpasswd file for the three users
2. Creates secret `htpasswd-maas-demo-users` in `openshift-config`
3. Merges identity provider `maas-demo-users` into cluster OAuth (keeps `rhbk`)
4. Applies group membership

Verify:

```bash
oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}{"\n"}'
# Expected: rhbk maas-demo-users

oc get group maas-demo-retail-analyst -o yaml
oc login -u demo-retail-analyst -p '<password-from-demo-users-passwords.env>' --server=<api-server>
oc whoami --show-groups
```

### 2. Subscriptions and auth policies (Day 6)

Each subscription `spec.owner.groups` and matching `MaaSAuthPolicy` subjects use persona groups (not `system:authenticated`):

- [day-6/manifests/demo-subscriptions.yaml](day-6/manifests/demo-subscriptions.yaml)
- [day-6/manifests/demo-auth-policies.yaml](day-6/manifests/demo-auth-policies.yaml)
- [day-6/manifests/demo-restrict-default-granite.yaml](day-6/manifests/demo-restrict-default-granite.yaml) — removes Day 5 `system:authenticated` Granite access so retail cannot use `granite-tiny-gpu-free` / catch-all auth
- [day-6/manifests/demo-maas-api-rbac.yaml](day-6/manifests/demo-maas-api-rbac.yaml) — `maas-viewer-role` bindings for key minting

### 3. RHOAI projects (Gen AI playground)

Playground configuration is stored as ConfigMaps in the **project namespace** you select in the RHOAI UI. Each persona should **create their own project** (they become namespace admin) — do **not** use read-only shared projects such as `grafana`.

| Persona | Suggested project |
|---------|-------------------|
| `demo-retail-analyst` | `maas-demo-retail` |
| `demo-risk-analyst` | `maas-demo-risk` |
| `demo-platform-ops` | `maas-demo-platform` |

**RHOAI UI:** project drop-down → **Create project** → enter name → **Create** → select project → **Try in playground**.

Full steps: [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md#step-01--create-rhoai-projects-before-playground).  
If you see `configmaps is forbidden`, see [06-troubleshooting.md](06-troubleshooting.md#gen-ai-playground--configmap-forbidden-wrong-project).

### 4. Per-user API key minting

[day-6/mint-persona-keys.sh](day-6/mint-persona-keys.sh) logs in as each htpasswd user and calls:

```bash
curl -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-retail-analyst-key","expiresIn":"336h","subscription":"demo-retail-analyst"}'
```

Output is written to `day-6/demo-users.env` (gitignored).

Re-mint after subscription changes:

```bash
./day-6/mint-persona-keys.sh
```

### 5. Demo traffic

[daily-traffic.sh](day-6/daily-traffic.sh) uses `DEMO_RETAIL_KEY`, `DEMO_RISK_KEY`, and `DEMO_PLATFORM_KEY` from `demo-users.env`:

```bash
source day-6/demo-users.env
./day-6/daily-traffic.sh --quick   # demo morning burst
./day-6/daily-traffic.sh          # full daily seed
```

### 6. Dashboard verification

**PromQL** (OpenShift Console → Observe → Metrics):

```promql
count by (user, subscription) (authorized_hits{subscription!=""})
```

Expected: three distinct `user` values (one per persona), each tied to its subscription.

**RHOAI Console:** Observe & monitor → Dashboard (Tech Preview) → MaaS usage — group by **user**.

See [day-6/OBSERVABILITY-TROUBLESHOOTING.md](day-6/OBSERVABILITY-TROUBLESHOOTING.md) if the Perses dashboard shows Service Unavailable.

---

## RBAC note

MaaS API key creation requires:

1. Valid OpenShift token (htpasswd user)
2. Membership in the subscription owner group
3. `maas-viewer-role` in `models-as-a-service` (via `demo-maas-api-rbac.yaml`)

**Gen AI playground** requires a **self-created RHOAI project** (namespace admin), not extra ClusterRoleBindings on shared namespaces.

If playground fails with **configmaps is forbidden**, create a dedicated project — see [06-troubleshooting.md](06-troubleshooting.md#gen-ai-playground--configmap-forbidden-wrong-project).

If minting fails with 403, check:

```bash
oc get rolebinding -n models-as-a-service | grep maas-demo
oc auth can-i create maassubscriptions --as=demo-retail-analyst -n models-as-a-service
```

Admin-only fallback (all metrics show `user=admin`):

```bash
# run-day6-install.sh falls back if demo-users-passwords.env is missing
TOKEN=$(oc whoami -t)
curl -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" ...
```

---

## Integration with install scripts

| Script | Multi-user behavior |
|--------|---------------------|
| `day-1/setup-multi-user.sh` | htpasswd IdP + persona groups |
| `day-1/run-day1-install.sh` | Calls `setup-multi-user.sh` if `demo-users-passwords.env` exists |
| `day-6/run-day6-install.sh` | Calls `mint-persona-keys.sh` when passwords file present |
| `day-6/daily-traffic.sh` | Unchanged — uses per-user keys from `demo-users.env` |

---

## Related docs

- [day-1/README.md](day-1/README.md) — Day 1 platform setup
- [day-6/README.md](day-6/README.md) — Observability personas
- [05-demonstration-steps.md](05-demonstration-steps.md) — Demo 6 showback script
