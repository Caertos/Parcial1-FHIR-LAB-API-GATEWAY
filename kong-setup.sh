#!/usr/bin/env bash
set -euo pipefail

KONG_ADMIN=${KONG_ADMIN:-http://localhost:8001}

echo "Creando service 'hapi-fhir-service' apuntando a http://hapi:8080"
curl -s -X POST $KONG_ADMIN/services --data "name=hapi-fhir-service" --data "url=http://hapi:8080" | jq || true

echo "Creando route '/fhir' para el service"
curl -s -X POST $KONG_ADMIN/services/hapi-fhir-service/routes --data 'paths[]=/fhir' --data 'methods[]=POST' --data 'methods[]=GET' | jq || true

echo "Adjuntando plugin rate-limiting con límites bajos (5/min)"
curl -s -X POST $KONG_ADMIN/services/hapi-fhir-service/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=5" \
  --data "config.policy=local" \
  --data "config.limit_by=consumer" \
  --data "config.fault_tolerant=false" | jq || true

echo "Listo. Verifique con: curl $KONG_ADMIN/services | jq"
