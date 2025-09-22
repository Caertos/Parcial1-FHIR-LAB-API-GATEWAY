#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATEWAY=${GATEWAY:-http://localhost:8000/fhir}
# HAPI exposes FHIR under /fhir path
HAPI_DIRECT=${HAPI_DIRECT:-http://localhost:8080/fhir}

echo "1) POST invalid Observation via Gateway -> esperar 400 o OperationOutcome"
HTTP_STATUS=$(curl -s -o /tmp/resp.txt -w "%{http_code}" -X POST "$GATEWAY/Observation" \
  -H "Content-Type: application/fhir+json" \
  --data-binary @"$ROOT_DIR/invalid_observation.json")

echo "HTTP status: $HTTP_STATUS"
echo "Body:" 
cat /tmp/resp.txt | jq || cat /tmp/resp.txt

if [[ "$HTTP_STATUS" != "400" && $(cat /tmp/resp.txt | jq -r '.resourceType // empty') != "OperationOutcome" ]]; then
  echo "Advertencia: la respuesta no es 400 ni OperationOutcome. Código: $HTTP_STATUS"
fi

echo
echo "2) POST \$validate via Gateway (encapsulado)"
HTTP_STATUS=$(curl -s -o /tmp/validate_resp.txt -w "%{http_code}" -X POST "$GATEWAY/Observation/\$validate" \
  -H "Content-Type: application/fhir+json" \
  --data-binary @"$ROOT_DIR/invalid_observation.json")

echo "HTTP status: $HTTP_STATUS"
echo "Body:" 
cat /tmp/validate_resp.txt | jq || cat /tmp/validate_resp.txt

echo
echo "3) Crear Patient y reintentar Observation (si necesita \$everything)"
PID=$(curl -s -X POST "$GATEWAY/Patient" -H "Content-Type: application/fhir+json" --data-binary @"$ROOT_DIR/patient.json" | jq -r '.id // .resource.id // empty')
if [[ -z "$PID" ]]; then
  echo "No se obtuvo ID de Patient. Intentando con HAPI directo..."
  PID=$(curl -s -X POST "$HAPI_DIRECT/Patient" -H "Content-Type: application/fhir+json" --data-binary @"$ROOT_DIR/patient.json" | jq -r '.id // .resource.id // empty')
fi
echo "Patient creado con id: $PID"

echo "Actualizar Observation inválido para referenciar patient y reintentar creación (esperamos aún error por valueQuantity)"
TMP_OBS=$(mktemp)
jq --arg pid "$PID" '.subject = {"reference": ("Patient/" + $pid)}' "$ROOT_DIR/invalid_observation.json" > $TMP_OBS
HTTP_STATUS=$(curl -s -o /tmp/resp2.txt -w "%{http_code}" -X POST "$GATEWAY/Observation" -H "Content-Type: application/fhir+json" --data-binary @$TMP_OBS)
echo "HTTP status: $HTTP_STATUS"
cat /tmp/resp2.txt | jq || cat /tmp/resp2.txt

echo
echo "4) Invocar \$everything para el paciente (si aplica)"
echo "GET $GATEWAY/Patient/$PID/\$everything"
curl -s -D /tmp/headers.txt "$GATEWAY/Patient/$PID/\$everything" -o /tmp/everything_body.txt || true
echo "Headers:" && cat /tmp/headers.txt || true
echo "Body:" && (jq '.' /tmp/everything_body.txt || cat /tmp/everything_body.txt)

echo
echo "5) Forzar rate limiting: ejecutar 30 request concurrentes rápidos para superar 5/min"
echo "Usaremos xargs para concurrencia; se esperan algunos 429"
seq 1 30 | xargs -n1 -P10 -I{} curl -s -o /dev/null -w "%{http_code} \n" -X GET "$GATEWAY/Patient/$PID" &> /tmp/rate_results.txt || true

echo "Resultados (conteo por código):"
cat /tmp/rate_results.txt | sort | uniq -c | sort -rn
echo "Muestras de respuestas 429 (si existen):"
grep -m5 "429" -n /tmp/rate_results.txt || echo "No se encontraron 429 en el registro local (intente bajar límites)"