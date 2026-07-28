# MaaS Client Test Access Guide (template)

Copy to **`CLIENT-TEST-ACCESS.md`** (gitignored), fill cluster URLs and passwords, then share with testers.

> PoC / sandbox only. Do not commit filled copies with real passwords or keys.

---

## Cluster endpoints

| Service | URL |
|---------|-----|
| OpenShift console | `https://console-openshift-console.<CLUSTER_DOMAIN>` |
| RHOAI dashboard | `https://rhods-dashboard-redhat-ods-applications.<CLUSTER_DOMAIN>` |
| MaaS gateway | `https://maas.<CLUSTER_DOMAIN>` |

Derive domain: `oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'`

**Login:** identity provider **`htpasswd_provider`**.

---

## Test users (htpasswd)

Password pattern: `{Username}-1234`

| User | Password | OpenShift group | Role narrative |
|------|----------|-----------------|----------------|
| Adam | `Adam-1234` | `maas-lob-retail` | Retail analyst |
| Brenda | `Brenda-1234` | `maas-lob-retail` | Retail analyst |
| Charlotte | `Charlotte-1234` | `maas-lob-risk` | Risk analyst |
| Daniel | `Daniel-1234` | `maas-lob-risk` | Risk analyst |
| Emma | `Emma-1234` | `maas-lob-platform` | Platform engineer |
| Francis | `Francis-1234` | `maas-lob-executive` | Executive / power user |

---

## Groups, subscriptions, and rate limits

| Group | Subscription | Priority | Models allowed | Token rate limit |
|-------|--------------|----------|----------------|------------------|
| `maas-lob-retail` | `lob-retail` | 40 | Llama 3.1 8B only | **100** / min |
| `maas-lob-risk` | `lob-risk` | 50 | Llama + Gemma | **400** / min each |
| `maas-lob-platform` | `lob-platform` | 60 | Llama + Gemma + external 70B | Locals **1000**; external **500** / min |
| `maas-lob-executive` | `lob-executive` | 70 | All three | Locals **5000**; external **2000** / min |

### Cost metadata

| Subscription | organizationId | costCenter |
|--------------|----------------|------------|
| `lob-retail` | `org-retail` | `CC-RETAIL-1001` |
| `lob-risk` | `org-risk` | `CC-RISK-2001` |
| `lob-platform` | `org-platform` | `CC-PLATFORM-3001` |
| `lob-executive` | `org-platform` | `CC-EXEC-4001` |

---

## Access matrix

| User | Llama 3.1 8B | Gemma 4 E4B | External 70B |
|------|:------------:|:-----------:|:------------:|
| Adam, Brenda | ✅ | ❌ 403 | ❌ 403 |
| Charlotte, Daniel | ✅ | ✅ | ❌ 403 |
| Emma, Francis | ✅ | ✅ | ✅ |

---

## Setup (operators)

```bash
./day-1/setup-client-test-users.sh
oc apply -f day-6/manifests/client-test-subscriptions.yaml
oc apply -f day-6/manifests/client-test-auth-policies.yaml
oc apply -f day-6/manifests/client-test-maas-api-rbac.yaml
oc apply -f day-6/manifests/client-test-restrict-free-subscriptions.yaml
```

See filled `CLIENT-TEST-ACCESS.md` for mint/curl examples and dashboard test steps.
