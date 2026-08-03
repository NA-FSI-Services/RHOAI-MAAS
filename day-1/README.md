# Day 1 Installation Results

**Completed:** 2026-06-05T18:21:03Z  
**Duration:** ~20 minutes (GPU node provisioning was the longest step)

---

## Summary

Day 1 exit criteria are **met** after remediation of a duplicate RHOAI OperatorGroup.

| Criterion | Result |
|-----------|--------|
| 3 allocatable GPUs | **Pass** — 3× g6e.2xlarge |
| Kuadrant Ready | **Pass** |
| maas-default-gateway Programmed | **Pass** |
| MaaS dependency CSVs | **Pass** (rhods Succeeded after OG cleanup) |
| Authorino TLS bootstrap | **Applied** |

**Not in Day 1 scope (Day 2):** `modelsAsService` Managed, PostgreSQL, model deployment, governance CRs.

---

## What was executed

1. **GPU scaling** — Patched MachineSets `ocp-fklhz-worker-gpu-big-us-east-2b/c` to 1 replica
2. **Operators** — Installed cert-manager + Leader Worker Set; verified RHCL, Service Mesh, Authorino, Limitador
3. **Platform config** — Verified Kuadrant, UWM, GatewayClass; confirmed gateway Programmed; applied Authorino annotation
4. **Remediation** — Removed duplicate `OperatorGroup/redhat-ods-operator` created by initial full operator apply
5. **Multi-user (optional)** — htpasswd IdP + persona groups via [setup-multi-user.sh](setup-multi-user.sh) — see [MULTI-USER-ACCESS.md](../MULTI-USER-ACCESS.md)

> **Advanced Guardrails:** Persona groups created here (`maas-demo-retail-analyst`, `maas-demo-risk-analytics`, `maas-demo-platform-ops`) are the **role/org identity** used by scoped guardrail demos on branch `advanced-guardrails` — see [09-advanced-guardrails-plan.md](../09-advanced-guardrails-plan.md).

---

## File index

| File | Description |
|------|-------------|
| [07-day1-summary.txt](07-day1-summary.txt) | Final cluster state summary |
| [CHANGES.md](CHANGES.md) | Plan deviations and conflict resolutions |
| [day1-install.log](day1-install.log) | Full installation log |
| [run-day1-install.sh](run-day1-install.sh) | Repeatable Day 1 script (updated) |
| [setup-multi-user.sh](setup-multi-user.sh) | Optional htpasswd IdP + demo groups |
| [manifests/demo-groups.yaml](manifests/demo-groups.yaml) | OpenShift groups for MaaS personas |
| [01-gpu-nodes-before.txt](01-gpu-nodes-before.txt) | GPU topology before scaling |
| [01-gpu-nodes-after-scale.txt](01-gpu-nodes-after-scale.txt) | GPU topology after scaling |
| [02-csv-openshift-operators.txt](02-csv-openshift-operators.txt) | Platform operator CSVs |
| [02-csv-rhods.txt](02-csv-rhods.txt) | RHOAI operator CSV |
| [08-rhods-og-cleanup.txt](08-rhods-og-cleanup.txt) | Duplicate OperatorGroup deletion |

---

## Next step: Day 2

```bash
cd ../work/rhoai-maas-guide
./scripts/setup-maas.sh --from-phase 3 --model granite-tiny-gpu
```

See [../04-installation-and-ready-state.md](../04-installation-and-ready-state.md) and [CHANGES.md](CHANGES.md).

---

## Compare to initial state

| Metric | Initial ([../initial-state](../initial-state)) | After Day 1 |
|--------|--------------------------------------------------|-------------|
| GPU nodes | 1 | **3** |
| rhods CSV | Succeeded | Succeeded (after fix) |
| cert-manager | Not installed | **Installed** |
| LWS operator | Not installed | **Installed** |
| Gateway bootstrap annotation | Missing | **Applied** |
| modelsAsService | Removed | Removed (Day 2) |
