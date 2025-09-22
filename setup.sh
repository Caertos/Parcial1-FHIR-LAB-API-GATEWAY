#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Iniciando el laboratorio FHIR + Kong con docker-compose..."
docker-compose -f "$ROOT_DIR/docker-compose.yml" up -d --remove-orphans

echo "Esperando a que Kong y HAPI estén listos..."
sleep 6

echo "Kong Admin: http://localhost:8001"
echo "Kong Proxy: http://localhost:8000/fhir/"  # nota: ruta configurada en kong.yml
echo "HAPI (directo): http://localhost:8080"

echo
echo "Si prefiere configurar Kong dinámicamente (en vez de declarative), ejecute: ./kong-setup.sh"
