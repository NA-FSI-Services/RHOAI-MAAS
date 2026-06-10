# Agent Collaboration Rules

Guidance for AI coding agents (Cursor, Copilot, etc.) working in this repository.

## Scope and safety

- **Minimize diff scope** — change only what the task requires; do not refactor unrelated install scripts or docs.
- **Never commit secrets** — API keys (`sk-oai-*`, workshop keys), htpasswd passwords, cluster tokens, or filled `.env` files. Use `.example` templates and [CONFIGURATION.md](CONFIGURATION.md).
- **Never commit client names** — avoid bank or customer identifiers in docs, manifests, or comments. Use generic terms: *enterprise*, *LOB team*, *demo persona*, *financial services*.
- **Do not push** unless the user explicitly asks. Preparing a clean tree is not the same as publishing.

## Repository conventions

- **MaaS URL:** `export MAAS_URL="https://maas.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"` — not `maas.apps.${CLUSTER_DOMAIN}` when the ingress domain already includes `apps.`.
- **Demo auth paths:** Use model-specific URLs (`/llm/<model>/v1/chat/completions`) for 401/403 demos; unified BBR behavior differs by cluster config.
- **Persona isolation:** Do not grant RBAC on shared namespaces (e.g. `grafana`) for playground access. Personas create their own RHOAI projects — see [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md#step-01--create-rhoai-projects-before-playground).
- **Day 6 Granite lockdown:** Retail personas must not get Granite via `system:authenticated` subscriptions or catch-all auth policies. Use [day-6/manifests/demo-restrict-default-granite.yaml](day-6/manifests/demo-restrict-default-granite.yaml).

## Scripts and manifests

- Prefer `command -v oc` over hardcoded `PATH` entries.
- Match existing shell style in `day-N/run-dayN-install.sh` (set -uo pipefail, `oc apply`, capture logs under `day-N/`).
- Kubernetes manifests: generic `organizationId` values (`org-retail`, `org-risk`, `org-platform`); cost centers like `CC-RETAIL-1001` are fine as demo metadata.
- Submodule / guide path: `work/rhoai-maas-guide` — do not vendor duplicate operator manifests unless the task requires it.

## Documentation

- Presenter scripts: [05-demonstration-steps.md](05-demonstration-steps.md) (terminal), [07-ui-based-demonstration-steps.md](07-ui-based-demonstration-steps.md) (RHOAI UI).
- Operational recovery: [06-troubleshooting.md](06-troubleshooting.md).
- Multi-user setup: [MULTI-USER-ACCESS.md](MULTI-USER-ACCESS.md).
- When adding env vars, update [CONFIGURATION.md](CONFIGURATION.md) and the matching `.example` file.

## Testing expectations

After gateway or auth changes, verify:

```bash
source day-3/demo-env.sh   # local only
curl -sk -o /dev/null -w "no-auth: %{http_code}\n" -X POST "${MAAS_URL}/llm/facebook-opt-125m-simulated/v1/chat/completions" \
  -H "Content-Type: application/json" -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Ping"}],"max_tokens":5}'
# Expect 401

curl -sk -o /dev/null -w "basic: %{http_code}\n" -X POST "${MAAS_URL}/llm/facebook-opt-125m-simulated/v1/chat/completions" \
  -H "Authorization: Bearer ${BASIC_USER_KEY}" -H "Content-Type: application/json" \
  -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Hello"}],"max_tokens":15}'
# Expect 200 (remint with ./day-3/remint-demo-keys.sh if 403)
```

## Git and PRs

- Follow existing day-folder structure (`day-1/` … `day-7/`, top-level `0N-*.md`).
- Commit messages: complete sentences, focus on *why*.
- Do not add `vids/` or install log artifacts — they are gitignored.

## When unsure

- Read [04-installation-and-ready-state.md](04-installation-and-ready-state.md) for install order.
- Read [day-N/CHANGES.md](day-6/CHANGES.md) for deviations from upstream rhoai-maas-guide.
- Ask before deleting install logs the user may rely on locally (they are gitignored, not removed from disk).
