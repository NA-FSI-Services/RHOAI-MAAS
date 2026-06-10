#!/usr/bin/env bash
# Create/refresh kuadrant-prometheus-datasource-secret for MaaS Perses dashboard.
set -euo pipefail
DAY6_DIR="$(cd "$(dirname "$0")" && pwd)"

oc apply -f "$DAY6_DIR/manifests/perses-thanos-reader-rbac.yaml"

TOKEN=$(oc create token maas-perses-thanos-reader -n redhat-ods-applications --duration=8760h)
oc create secret generic kuadrant-prometheus-datasource-secret \
  -n redhat-ods-applications \
  --from-literal=authorization="Bearer ${TOKEN}" \
  --dry-run=client -o yaml | oc apply -f -

oc annotate persesdatasource kuadrant-prometheus-datasource -n redhat-ods-applications \
  maas.opendatahub.io/reconcile="$(date -u +%s)" --overwrite >/dev/null

echo "kuadrant-prometheus-datasource-secret updated"
oc get persesdatasource kuadrant-prometheus-datasource -n redhat-ods-applications \
  -o jsonpath='Available={.status.conditions[?(@.type=="Available")].status}{"\n"}'
