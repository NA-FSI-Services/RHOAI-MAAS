# Configuration and Secrets

This repository **does not** store API keys, workshop provider keys, or htpasswd passwords. Copy the `.example` files below and fill in values for your cluster.

## Required before demos

| File | Copy from | Purpose |
|------|-----------|---------|
| `day-3/demo-env.sh` | [day-3/demo-env.sh.example](day-3/demo-env.sh.example) | `BASIC_USER_KEY`, `ADVANCED_USER_KEY` for Demo 2 auth scenarios |
| `day-6/demo-users.env` | [day-6/demo-users.env.example](day-6/demo-users.env.example) | Persona API keys for multi-user observability demos |

Generate keys instead of hand-editing:

```bash
./day-3/remint-demo-keys.sh          # writes day-3/demo-env.sh
./day-6/mint-persona-keys.sh         # writes day-6/demo-users.env (needs passwords file)
```

## Multi-user htpasswd (optional)

| File | Copy from | Purpose |
|------|-----------|---------|
| `day-1/demo-users-passwords.env` | [day-1/demo-users-passwords.env.example](day-1/demo-users-passwords.env.example) | htpasswd passwords for `demo-retail-analyst`, `demo-risk-analyst`, `demo-platform-ops` |

Then run `./day-1/setup-multi-user.sh`.

## External model provider (Day 5)

| File | Copy from | Purpose |
|------|-----------|---------|
| `day-5/provider-key.env` | [day-5/provider-key.env.example](day-5/provider-key.env.example) | Remote LiteLLM / workshop endpoint URL and provider API key |

## OpenShift Lightspeed (Day 7, optional)

| File | Copy from | Purpose |
|------|-----------|---------|
| `day-7/lightspeed-maas.env` | [day-7/lightspeed-maas.env.example](day-7/lightspeed-maas.env.example) | MaaS API key used by Lightspeed |

Or run `./day-7/run-day7-install.sh` (mints key and writes `lightspeed-maas.env`).

## Cluster URLs

Do not hardcode hostnames in committed files. Derive at runtime:

```bash
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
export MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
```

On many clusters, `CLUSTER_DOMAIN` already includes the `apps.` prefix (e.g. `apps.ocp.example.com`). Do **not** use `maas.apps.${CLUSTER_DOMAIN}` — that double-prefixes `apps.`.

## Pre-push checklist

```bash
# No real keys in tracked files
git grep -E 'sk-oai-|sk-lnz|DemoRetail1!' -- ':!*.example' ':!.gitignore'

# No client-specific names (adjust pattern as needed)
git grep -iE 'wells fargo' || true

# Secret files stay local
test ! -f day-3/demo-env.sh || git check-ignore -q day-3/demo-env.sh
```

All paths listed under **Local secrets** in [.gitignore](.gitignore) must remain untracked.
