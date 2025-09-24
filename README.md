# Laboratorio: Validación FHIR y Observabilidad a través de Kong (rate-limiting)

Este laboratorio cubre:

- Requisitos y comprobaciones previas.
- Cómo levantar el entorno con Docker Compose.
- Cómo probar los endpoints (por Gateway y directo a HAPI).
- Qué hacen los scripts incluidos (`setup.sh`, `tests.sh`, `inject.sh`, `kong-setup.sh`).
- Cómo interpretar las respuestas y logs (incluyendo OperationOutcome y 429).
- Cómo limpiar el entorno por completo (detener y eliminar contenedores, imágenes y redes).

IMPORTANTE: los comandos aquí asumen que trabajas sobre la carpeta del repositorio: `/media/caertos/DC/ProyectosWeb/docker/Parcial1`.

Índice
1) Requisitos
2) Preparar el repositorio
3) Levantar el laboratorio (paso a paso)
4) Probar manualmente endpoints (comandos y qué buscar)
5) Ejecutar el flujo automático (`tests.sh`) y entender la salida
6) Hacer inyección masiva con `inject.sh` (opcional)
7) Logs y troubleshooting detallado
8) Ajustar límites (si necesitas menos 429)
9) Limpieza completa (stop + remove images etc.)

---------------------------------------------------------------------------------------------------

1) Requisitos

- Docker (motor) y Docker Compose v2 (o docker-compose). Comprueba:

```bash
docker info >/dev/null && echo "Docker OK" || echo "Docker no disponible"
docker compose version || docker-compose version
```

- `curl` y `jq` en el host son muy útiles para formatear JSON. Comprueba:

```bash
curl --version
jq --version
```

Si no tienes `jq`, instálalo (Ubuntu/Debian):

```bash
sudo apt update
sudo apt install -y jq
```

2) Preparar el repositorio

Desde la ruta del laboratorio:

```bash
cd /media/caertos/DC/ProyectosWeb/docker/Parcial1
# Dar permisos de ejecución a los scripts
chmod +x setup.sh kong-setup.sh tests.sh inject.sh
```

3) Levantar el laboratorio (paso a paso)

1. Inicia el stack con Docker Compose (modo detached):

```bash
docker compose up -d --remove-orphans
```

Qué esperar:
- Docker descargará imágenes si no están presentes.
- Debes ver contenedores: `hapi_fhir`, `kong_gateway`, `fhir_client`.

Verifica estado:

```bash
docker compose ps
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

Si Kong tardase en estar listo, espera unos segundos y vuelve a comprobar.

4) Probar manualmente endpoints

Objetivo: comprobar que HAPI responde directamente y que Kong está proxying correctamente por `/fhir`.

- Probar HAPI directo:

```bash
curl -s http://localhost:8080/fhir/metadata | jq
```

Salida esperada: JSON con resourceType CapabilityStatement.

- Probar vía Kong (proxy):

```bash
curl -s http://localhost:8000/fhir/metadata | jq
```

Si `jq` lanza un error de parseo, usa `curl -i` para inspeccionar cabeceras:

```bash
curl -i http://localhost:8000/fhir/metadata | sed -n '1,200p'
```

Cabeceras importantes:
- `Content-Type` (debe ser application/fhir+json o application/fhir+xml).
- `X-Kong-Upstream-Latency` y `X-Kong-Proxy-Latency` para medir latencias.

5) Ejecutar el flujo automático (`tests.sh`)

`tests.sh` realiza 5 pasos: POST inválido, $validate, crear Patient, $everything, forzar rate-limit.

```bash
./tests.sh
```

Explicación detallada de lo que hace y qué salida verás:

- Paso 1: POST `/fhir/Observation` con `invalid_observation.json`.
  - Esperado: HTTP 400 y un `OperationOutcome` explicando que `valueQuantity.value` no es numérico.

- Paso 2: POST `/fhir/Observation/$validate` con el mismo body.
  - Esperado: HTTP 400 y `OperationOutcome` de validación.

- Paso 3: Crear un `Patient` vía gateway. Si Kong aplica rate-limit y devuelve `429`, el script reintenta directamente contra HAPI (`http://localhost:8080/fhir`).
  - Salida útil: verás el `id` creado. Ejemplo: `Patient creado con id: 2`.

- Paso 4: Invocar `GET /fhir/Patient/{id}/$everything` y mostrar headers + body (Bundle).

- Paso 5: Forzar rate-limiter: se lanzan 30 requests concurrentes a `/fhir/Patient/{id}`.
  - Salida esperada: varios `429` (dependiendo del límite en `kong.yml`).

Si quieres ver en detalle las respuestas intermedias, revisa los archivos temporales que el script crea en `/tmp` (por ejemplo `/tmp/resp.txt`, `/tmp/validate_resp.txt`, `/tmp/resp2.txt`, `/tmp/everything_body.txt`, `/tmp/rate_results.txt`).

6) Inyección masiva con `inject.sh` (opcional)

Este script crea N pacientes y para cada uno crea Observations, dejando cada 5º Observation inválido. Uso:

```bash
./inject.sh 50
```

Registros:
- `/tmp/fhir_inject_results.csv` con `index,patient_id,http_status`.
- Respuestas de cada Observation en `/tmp/obs_resp_<index>.json`.

7) Logs y troubleshooting detallado

- Ver logs de Kong y HAPI:

```bash
docker logs -f kong_gateway
docker logs -f hapi_fhir
```

- Si Kong devuelve `502 Bad Gateway` con body `{"message":"An invalid response was received from the upstream server"}`:
  - Comprueba que la ruta enviada al upstream es correcta (por ejemplo, que Kong no esté eliminando `/fhir` al reenviar). En `kong.yml` la opción `strip_path: false` asegura que Kong reenvíe `/fhir/metadata` como `/fhir/metadata` al backend.

- Si recibes `429 Too Many Requests` en operaciones de creación:
  - Revisa el header `Retry-After` y el plugin rate-limiting en `kong.yml`.
  - Opciones para pruebas: reducir temporalmente la configuración `minute` o comentar el plugin.

- Si HAPI devuelve `404` en rutas directas (ej. `/Patient` en lugar de `/fhir/Patient`):
  - Usa siempre `/fhir` prefix cuando haces requests directos al contenedor HAPI en este laboratorio (HAPI expone recursos en `/fhir`).

8) Ajustar límites de Kong (para demo sin 429)

Edita `kong.yml` y ajusta/elimina el plugin `rate-limiting`. Ejemplo para reducir el efecto:

```yaml
plugins:
  - name: rate-limiting
    service: hapi-fhir-service
    config:
      minute: 1000
      policy: local
      limit_by: consumer
      fault_tolerant: false
```

Luego reinicia Kong:

```bash
docker restart kong_gateway
```

9) Limpieza completa (detener y eliminar todo)

Si quieres eliminar todo lo que el laboratorio creó (contenedores, imágenes descargadas, red), sigue estos pasos desde la carpeta del proyecto:

```bash
# 1) Parar y remover contenedores y red del compose
docker compose down --remove-orphans

# 2) Listar contenedores relacionados (si aún existen)
docker ps -a --filter "name=hapi_fhir" --filter "name=kong_gateway" --filter "name=fhir_client"

# 3) Eliminar contenedores manualmente (si quedaran)
docker rm -f kong_gateway hapi_fhir fhir_client || true

# 4) Eliminar imágenes descargadas (advertencia: esto borra las imágenes locales)
docker image rm -f hapiproject/hapi:latest kong:3.3 curlimages/curl:7.88.1 || true

# 5) (Opcional) eliminar volúmenes huérfanos y redes
docker volume prune -f || true
docker network rm parcial1_default || true
```

Notas importantes sobre limpieza:
- `docker image rm -f` eliminará las imágenes locales; si las necesitas después, Docker las volverá a descargar al levantar el compose.
- No ejecutes `docker system prune -a` a menos que quieras eliminar absolutamente todo en tu host.

