# Laboratorio: Validación FHIR y Observabilidad a través de Kong (rate-limiting)

Este laboratorio levanta un servidor HAPI FHIR y un Kong Gateway (modo DB-less) localmente con Docker. Permite:

- Enviar un Observation inválido (valor no numérico en valueQuantity) a través del Gateway.
- Invocar el operation $validate para obtener un OperationOutcome.
- Crear un Patient y ejecutar $everything.
- Forzar rate-limiting para obtener 429 y revisar logs.

Requisitos previos
- Docker y docker-compose.
- curl, jq (en el host) o usar el contenedor `client` provisto.

Archivos en este directorio
- `docker-compose.yml` - levanta HAPI, Kong (DB-less) y un contenedor cliente.
- `kong.yml` - configuración declarative de Kong (service/route/plugin rate-limiting).
- `setup.sh` - script para levantar los servicios.
- `kong-setup.sh` - alternativa para configurar Kong via Admin API dinámicamente.
- `tests.sh` - script de pruebas: POST inválido, $validate, crear patient, ejecutar $everything, forzar rate-limit.
- `invalid_observation.json` - Observation inválido provisto por el enunciado.
- `patient.json` - recurso Patient de ejemplo.
- `apigee-policy-sample.xml` - ejemplo de policy para Apigee (alternativa).

Pasos rápidos

1) Levantar el laboratorio:

```bash
chmod +x setup.sh kong-setup.sh tests.sh
./setup.sh
```

2) (Opcional) Si prefiere configurar Kong dinámicamente en lugar de usar `kong.yml` (DB-less):

```bash
./kong-setup.sh
```

3) Ejecutar pruebas:

```bash
./tests.sh
```

Cómo ejecutar `inject.sh` (inyección masiva de recursos)
-----------------------------------------------------

`inject.sh` permite inyectar una serie de recursos (Patients + Observations) a través del Gateway para stress testing y validación. Por defecto inyecta 50 recursos y guarda un registro en `/tmp/fhir_inject_results.csv`.

Requisitos: `curl` y `jq` en el host (si no los tiene, puede ejecutar el script dentro del contenedor `fhir_client` con una imagen que tenga estas utilidades).

Ejemplos:

1) Dar permiso de ejecución:

```bash
chmod +x inject.sh
```

2) Ejecutar (50 por defecto):

```bash
./inject.sh
```

3) Ejecutar con número de recursos distinto (por ejemplo 100):

```bash
./inject.sh 100
```

Salida y análisis rápido
- Archivo de registro: `/tmp/fhir_inject_results.csv` con columnas: index,patient_id,http_status

Comandos útiles:

```bash
# Ver últimas 10 entradas
tail -n 10 /tmp/fhir_inject_results.csv

# Resumen por código HTTP
tail -n +2 /tmp/fhir_inject_results.csv | awk -F, '{print $3}' | sort | uniq -c | sort -rn

# Ver índices con error (no 200/201)
awk -F, '$3!~/(200|201)/{print $0}' /tmp/fhir_inject_results.csv

# Revisar body de respuesta de un índice concreto (ej: 5)
cat /tmp/obs_resp_5.json | jq '.' || cat /tmp/obs_resp_5.json
```

Ejecución dentro del contenedor `fhir_client` (opcional)
- Copiar los archivos y ejecutar dentro del contenedor si el host no tiene `jq`:

```bash
docker cp . fhir_client:/workdir
docker exec -it fhir_client sh -c "cd /workdir && chmod +x inject.sh && ./inject.sh 50"
```

- Nota: algunas imágenes de `curl` no incluyen `jq` ni `bash`. Si lo necesitas, puedes usar una imagen `ubuntu` o `alpine` con herramientas instaladas.

Parámetros y ajustes dentro del script
- `inject.sh` acepta un argumento: número de recursos a generar.
- El script inserta un Observation inválido cada 5º registro por defecto; puedes cambiar la lógica dentro del script si quieres otro patrón.
- Ajusta la pausa `sleep 0.05` para controlar la velocidad de inyección y provocar o evitar que el rate-limiter se dispare.

Interpretación práctica
- 201/200: inserción exitosa.
- 400 u OperationOutcome: validación fallida (tal como buscamos en este laboratorio).
- 429: Kong ha limitado tráfico — revisar logs de Kong y header `Retry-After`.


Comandos explicados y outputs esperados

- POST /fhir/Observation (vía Gateway): HTTP 400 o 201 con OperationOutcome. Ejemplo esperado:

  - Código HTTP: 400
  - Body: OperationOutcome con entradas que describen que `valueQuantity.value` no es numérico.

  Fragmento de OperationOutcome esperado (ejemplo):

  {
    "resourceType": "OperationOutcome",
    "issue": [
      {
        "severity": "error",
        "code": "invalid",
        "diagnostics": "Invalid value for element valueQuantity.value: expected number"
      }
    ]
  }

- POST /fhir/Observation/$validate: devuelve OperationOutcome con errores de validación.

- GET /fhir/Patient/{id}/$everything: devuelve un `Bundle` o un error si no hay recursos.

- Forzar rate limit: con la configuración `minute: 5` (en `kong.yml`) hacemos 30 peticiones concurrentes; se esperan varias respuestas `429`.

Ver logs

- Logs de Kong (proxy/admin) visibles vía docker logs:

```bash
docker logs -f kong_gateway
docker logs -f hapi_fhir
```

- Filtrar accesos 429 en logs de Kong:

```bash
docker logs kong_gateway 2>&1 | grep " 429 " || true
```

- En HAPI FHIR logs se esperan entradas indicando validación fallida. Buscar `Validation` o `OperationOutcome`:

```bash
docker logs hapi_fhir 2>&1 | grep -i "validation" || true
docker logs hapi_fhir 2>&1 | grep -i "operationoutcome" || true
```

Criterios de aceptación

1) POST del Observation inválido (vía Gateway) devuelve `400` o `OperationOutcome`. (tests.sh chequea esto y muestra body).
2) POST a `$validate` devuelve `OperationOutcome` con detalles. (tests.sh imprime la respuesta).
3) Tras suficientes solicitudes concurrentes, Kong devuelve `429`. (tests.sh cuenta códigos y muestra 429 si aparecen).

Troubleshooting

- Si no aparecen 429:
  - Bajar los límites en `kong.yml` (por ejemplo `minute: 2`) y reiniciar Kong.
  - Asegurarse de que la ruta usada por tests es exactamente `/fhir` (proxy prefix).

- Si HAPI responde 404 desde Kong:
  - Verifique que `services[0].url` en `kong.yml` apunte a `http://hapi:8080` y que el contenedor `hapi` esté sano.

- Si $everything devuelve 500 o error:
  - Asegúrese que el Patient tiene recursos vinculados (Observation creado con subject correcto).

Apigee (alternativa)

Si quisiera aplicar la misma limitación en Apigee Edge/Apigee X, aquí hay dos políticas ejemplares (Quota y SpikeArrest). No se pueden ejecutar localmente sin una cuenta Apigee.

Archivo de ejemplo: `apigee-policy-sample.xml`

---
