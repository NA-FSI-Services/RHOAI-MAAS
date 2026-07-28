#!/usr/bin/env bash
# Raise data-science-gateway (rh-ai) memory to avoid OOMKill / CrashLoopBackOff → HTTP 503.
# OpenShift Gateway parametersRef ConfigMap accepts a `deployment` overlay (same as maas-gateway-options).
set -euo pipefail

NS=openshift-ingress
CM=data-science-gateway-config

if ! oc get cm "$CM" -n "$NS" >/dev/null 2>&1; then
  echo "ConfigMap ${NS}/${CM} not found — is RHOAI GatewayConfig provisioned?"
  exit 1
fi

SERVICE=$(oc get cm "$CM" -n "$NS" -o jsonpath='{.data.service}')
if [ -z "$SERVICE" ]; then
  SERVICE='metadata:
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: "data-science-gateway-service-tls"
spec:
  type: ClusterIP
'
fi

DEPLOYMENT='spec:
  template:
    spec:
      containers:
      - name: istio-proxy
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
          limits:
            cpu: "2"
            memory: 2Gi
'

oc create cm "$CM" -n "$NS" \
  --from-literal=service="$SERVICE" \
  --from-literal=deployment="$DEPLOYMENT" \
  --dry-run=client -o yaml | oc apply -f -

# Force gateway controller to rebuild Deployment from parametersRef
oc delete deploy -n "$NS" -l gateway.networking.k8s.io/gateway-name=data-science-gateway --ignore-not-found
echo "Waiting for data-science-gateway Ready..."
for i in $(seq 1 48); do
  line=$(oc get pods -n "$NS" -l gateway.networking.k8s.io/gateway-name=data-science-gateway --no-headers 2>/dev/null | head -1 || true)
  echo "  [$i] $line"
  echo "$line" | grep -Eq '1/1[[:space:]]+Running' && break
  sleep 5
done

MEM=$(oc get pods -n "$NS" -l gateway.networking.k8s.io/gateway-name=data-science-gateway \
  -o jsonpath='{.items[0].spec.containers[0].resources.limits.memory}' 2>/dev/null || true)
echo "memory limit: ${MEM:-unknown}"
[ "$MEM" = "2Gi" ] || echo "WARNING: expected 2Gi — check Gateway parametersRef / ConfigMap"
