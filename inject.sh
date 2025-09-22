#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATEWAY=${GATEWAY:-http://localhost:8000/fhir}
COUNT=${1:-50}

LOG_FILE="/tmp/fhir_inject_results.csv"
echo "index,patient_id,http_status" > "$LOG_FILE"

echo "Inyectando $COUNT recursos (variando válidos/invalidos) vía $GATEWAY"
for i in $(seq 1 $COUNT); do
  # Crear paciente
  PATIENT_PAYLOAD=$(cat <<JSON
{
  "resourceType": "Patient",
  "name": [{"family": "Auto", "given": ["User$i"]}],
  "gender": "unknown"
}
JSON
)

  curl -s -o /tmp/patient_resp_$i.json -w "%{http_code}" -X POST "$GATEWAY/Patient" \
    -H "Content-Type: application/fhir+json" \
    --data-binary "$PATIENT_PAYLOAD" > /dev/null

  PID=$(jq -r '.id // .resource.id // empty' /tmp/patient_resp_$i.json 2>/dev/null || true)
  if [[ -z "$PID" ]]; then
    # fallback: try to read Location header (if any)
    PID="unknown"
  fi

  # Selección: cada 5º registro usamos el Observation inválido exacto (proporcionado)
  if (( i % 5 == 0 )); then
    TMP_OBS=$(mktemp)
    jq --arg pid "$PID" '.subject = {"reference":"Patient/" + $pid}' "$ROOT_DIR/invalid_observation.json" > "$TMP_OBS"
    HTTP_STATUS=$(curl -s -o /tmp/obs_resp_$i.json -w "%{http_code}" -X POST "$GATEWAY/Observation" \
      -H "Content-Type: application/fhir+json" \
      --data-binary @"$TMP_OBS") || HTTP_STATUS="000"
    rm -f "$TMP_OBS"
  else
    # Observation válido con valor numérico aleatorio
    VALUE=$(( (RANDOM % 120) + 40 ))
    OBS_PAYLOAD=$(cat <<JSON
{
  "resourceType":"Observation",
  "status":"final",
  "code":{ "coding":[{"system":"http://loinc.org","code":"8480-6","display":"Systolic BP"}]},
  "subject": {"reference": "Patient/$PID"},
  "valueQuantity": {"value": $VALUE, "unit": "mmHg"}
}
JSON
)
    HTTP_STATUS=$(curl -s -o /tmp/obs_resp_$i.json -w "%{http_code}" -X POST "$GATEWAY/Observation" \
      -H "Content-Type: application/fhir+json" \
      --data-binary "$OBS_PAYLOAD") || HTTP_STATUS="000"
  fi

  echo "$i,$PID,$HTTP_STATUS" >> "$LOG_FILE"
  printf "[%02d] patient:%s status:%s\n" "$i" "$PID" "$HTTP_STATUS"

  # pequeña pausa para no saturar instantáneamente (ajustable)
  sleep 0.05
done

echo "Inyección completada. Registro: $LOG_FILE"
echo "Resumen por código:"
tail -n +2 "$LOG_FILE" | awk -F, '{print $3}' | sort | uniq -c | sort -rn
