# Day 2 / RHOAI 3.5-ea deviations

Branch: `rhoai-3.5-ea`

## Versus RHOAI 3.4 PoC / rhoai-maas-guide

| Area | 3.4 guide / main | 3.5.0-ea.2 (this branch) |
|------|------------------|---------------------------|
| Channel | `stable-3.x` | `beta`, CSV `rhods-operator.3.5.0-ea.2` |
| OperatorGroup | empty (AllNamespaces) | Same — OwnNamespace **fails** |
| AI Gateway | via KServe MaaS only | `aigateway.managementState: Managed` + auto `GatewayConfig/default-gateway` → `data-science-gateway` |
| MaaS switch | `kserve.modelsAsService` | **Still** `kserve.modelsAsService` on EA2 CRD (upstream docs may already show `aigateway.modelsAsAService`) |
| Gateway | `maas-default-gateway` + `maas-gateway-options` ConfigMap | Required; also create Route `maas-gateway-route` (passthrough) for `maas.${CLUSTER_DOMAIN}` |
| Models | granite-tiny-gpu + simulator | Llama 3.1 8B FP8 ModelCar + Gemma 4 E4B (HF) — [manifests/models/](manifests/models/) |
| Hardware profile | guide `nvidia-l4-profile` (optional) | [hardwareprofile-nvidia-l4.yaml](manifests/hardwareprofile-nvidia-l4.yaml) — Node scheduling to `nvidia.com/gpu.product=NVIDIA-L4`; LLMIS annotated `opendatahub.io/hardware-profile-name=nvidia-l4-gpu` |
| vLLM runtime | `rhaiis/vllm-cuda-rhel9:3.3.0` | `rhaii-early-access/vllm-cuda-rhel9@sha256:…` (CSV relatedImage; required for `gemma4`) |
| Subscription priority | often all `10` | Unique priorities required (SharedPriority) — Llama `10`, Gemma `20` |

## Install artifacts

- [datasciencecluster-3.5-ea.yaml](manifests/datasciencecluster-3.5-ea.yaml)
- [hardwareprofile-nvidia-l4.yaml](manifests/hardwareprofile-nvidia-l4.yaml)
- [08-rhoai-3.5-ea-install.md](../08-rhoai-3.5-ea-install.md)
- [day-1/run-day1-gpu-operators.sh](../day-1/run-day1-gpu-operators.sh)

## Advanced Guardrails track

Branch `advanced-guardrails` (from this EA baseline) keeps TrustyAI Managed so NeMo CRDs exist. No extra Day 2 models are required for scoped/provider demos — see [09-advanced-guardrails-plan.md](../09-advanced-guardrails-plan.md) and Day 4 advanced manifests.
