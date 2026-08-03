# Day 7 Installation Results

**Focus:** OpenShift Lightspeed → MaaS gateway (**local Llama 3.1 8B Instruct**)

---

## Summary

Day 7 wires **OpenShift Lightspeed** to the same **MaaS gateway** so the console assistant consumes governed **local Llama** inference.

| Criterion | Result |
|-----------|--------|
| Lightspeed Operator | Installed (`lightspeed-operator` CSV Succeeded) |
| Llama tool-calling flags | `--enable-auto-tool-choice` + `--tool-call-parser=llama3_json` |
| OLSConfig → MaaS Llama | `maas-gateway` / `llama-3-1-8b-instruct` |
| `lightspeed-app-server` Ready | Yes |
| Console plugin | `lightspeed-console-plugin` enabled |
| MaaS plain chat probe | HTTP 200 |
| MaaS `tool_choice: auto` via gateway | HTTP 400 (empty body) — vLLM in-pod returns 200; gateway/ExtProc path issue |

---

## Architecture

```
OpenShift Console (Lightspeed UI)
  → lightspeed-app-server
  → MaaS Gateway (${MAAS_URL}/llm/llama-3-1-8b-instruct/v1)
  → Authorino + quotas (demo-openshift-lightspeed)
  → Llama 3.1 8B Instruct (local GPU)
```

---

## Install

```bash
./day-7/run-day7-install.sh
```

Creates / updates:

- Lightspeed Operator subscription (if missing)
- Llama LLMIS tool-calling args
- `HTTPRoute/bbr-llama-3-1-8b-instruct` for unified `/v1` routing
- `demo-openshift-lightspeed` subscription (50k TPM/min, `CC-LIGHTSPEED-4001`)
- `maas-gateway-api-key` secret + `OLSConfig/cluster`
- `day-7/lightspeed-maas.env` (gitignored)

---

## Demo

1. Open **OpenShift Console** (cluster-admin)
2. Click the **Lightspeed** icon in the header
3. Ask a cluster question (e.g. *“How do I list GPU nodes?”*)

Talking point: answers come from **local Llama via MaaS** — same gateway auth and quotas as app traffic.

---

## File index

| File | Description |
|------|-------------|
| [run-day7-install.sh](run-day7-install.sh) | Install script |
| [manifests/lightspeed-operator-subscription.yaml](manifests/lightspeed-operator-subscription.yaml) | Operator install |
| [manifests/llama-tool-calling-patch.yaml](manifests/llama-tool-calling-patch.yaml) | Tool-calling args reference |
| [manifests/bbr-llama-httproute.yaml](manifests/bbr-llama-httproute.yaml) | Unified BBR for Llama |
| [manifests/demo-lightspeed-subscription.yaml](manifests/demo-lightspeed-subscription.yaml) | MaaS subscription |
| [manifests/demo-lightspeed-auth-policy.yaml](manifests/demo-lightspeed-auth-policy.yaml) | Auth policy |
| [manifests/olsconfig-maas-gateway.yaml](manifests/olsconfig-maas-gateway.yaml) | OLSConfig template |

> **Advanced Guardrails:** Day 7 is unchanged. Lightspeed prompts are not wired through NeMo in this PoC; content-policy demos stay on Day 4/5 presenter scripts — [09-advanced-guardrails-plan.md](../09-advanced-guardrails-plan.md).

