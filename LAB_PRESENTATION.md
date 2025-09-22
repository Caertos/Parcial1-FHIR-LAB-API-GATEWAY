# Presentación del laboratorio: Validación FHIR + Gateway (Kong) con rate-limiting

Este documento sirve como guía para exponer el laboratorio en una demo, reunión técnica, o sesión de formación. Contiene objetivos, mensajes clave, pasos para la demo en vivo, métricas a mostrar y respuestas a preguntas frecuentes.

1. Mensaje principal
--------------------

Demostrar cómo un API Gateway (Kong) puede mediar el tráfico hacia un servidor HAPI FHIR, aplicando políticas de control de tráfico (rate-limiting) y permitiendo validar recursos FHIR antes de su ingreso al backend; además mostrar cómo observar (logs) y comprobar que validaciones y rechazos por límites ocurren correctamente.

2. Objetivos de la demo
-----------------------
- Mostrar la validación de recursos FHIR (Observation) y el resultado en OperationOutcome.
- Mostrar trazabilidad y logs cuando ocurren validaciones fallidas.
- Forzar rate limiting y mostrar 429 en responses y en logs del Gateway.
- Enseñar cómo inyectar datos masivos (script `inject.sh`) y cómo interpretar resultados.

3. Audiencia
-----------
- SRE/DevOps que implementan API Gateways y políticas.
- Integradores FHIR que quieren comprobar seguridad y calidad de datos.
- Equipos de producto que necesiten entender efectos de throttling en integraciones FHIR.

4. Equipamiento y precondiciones
--------------------------------
- Laptop con Docker y docker-compose.
- Puertos 8000 (Kong proxy), 8001 (admin), 8080 (HAPI) libres.
- Archivo del laboratorio en repositorio (los scripts ya están presentes).

5. Estructura sugerida de la demo (tiempos aproximados)
------------------------------------------------------
- 0:00-1:30 — Intro corta (qué vamos a probar y por qué importa).
- 1:30-3:00 — Levantar el laboratorio: ejecutar `./setup.sh`.
- 3:00-6:00 — Mostrar endpoint Gateway: curl básico a /fhir/metadata y /fhir/Patient.
- 6:00-10:00 — Enviar Observation inválido (POST) y mostrar OperationOutcome + logs en HAPI.
- 10:00-13:00 — Ejecutar $validate y detallar el OperationOutcome.
- 13:00-18:00 — Ejecutar `inject.sh 50` para subir 50 recursos (algunos inválidos) y mostrar CSV con resultados.
- 18:00-22:00 — Forzar rate-limit con `tests.sh` o con `seq|xargs` y mostrar 429 en respuestas y en logs de Kong.
- 22:00-25:00 — Q&A y conclusiones.

6. Demo paso a paso (comandos listos para copiar)
------------------------------------------------
- Levantar lab:
```bash
chmod +x setup.sh kong-setup.sh tests.sh inject.sh
./setup.sh
```
- Ver metadata HAPI vía Kong (prueba básica):
```bash
curl -s http://localhost:8000/fhir/metadata | jq
```
- Enviar Observation inválido:
```bash
curl -i -X POST http://localhost:8000/fhir/Observation \
  -H "Content-Type: application/fhir+json" --data-binary @invalid_observation.json
```
- Ejecutar validación explícita:
```bash
curl -i -X POST http://localhost:8000/fhir/Observation/\$validate \
  -H "Content-Type: application/fhir+json" --data-binary @invalid_observation.json
```
- Inyectar 50 recursos (muestra de carga):
```bash
./inject.sh 50
# Revisar /tmp/fhir_inject_results.csv
```
- Forzar rate-limiting (ejemplo rápido):
```bash
seq 1 30 | xargs -n1 -P10 -I{} curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/fhir/Patient/<id>
```

7. Métricas/artefactos que mostrar durante la presentación
-----------------------------------------------------------
- OperationOutcome devuelto por HAPI ($validate).
- CSV de `inject.sh` con conteo de 201/400 por recurso insertado.
- Logs del Gateway mostrando 429 y header Retry-After.
- Timestamps para correlacionar petición <-> log.

8. Preguntas frecuentes y respuestas técnicas
-------------------------------------------
- ¿Por qué rate-limiting en un Gateway y no en la app? — El Gateway centraliza políticas y evita que clientes maliciosos o bugs colapsen backends; además aplica límites por consumidor y ofrece metadatos de rechazo (Retry-After).
- ¿HAPI valida automáticamente? — Depende de la configuración; $validate es la forma segura de obtener OperationOutcome explícito.
- ¿Cómo persistir logs y métricas? — Integrar Kong con un stack ELK/EFK o con Prometheus + Grafana; HAPI puede exportar logs y métricas a lo mismo.

9. Recomendaciones para producción
----------------------------------
- Usar Kong con base de datos (Postgres) para persistencia y múltiples instancias.
- Configurar límites por consumidor, por credential y rutas críticas.
- Aplicar autenticación (key-auth, jwt) y observabilidad (tracing, metrics).

10. Slides / Script de presentación (resumen para speaker)
-------------------------------------------------------
- Slide 1: Título y contexto (objetivos).
- Slide 2: Arquitectura (client -> Kong -> HAPI FHIR).
- Slide 3: Demo 1: Validación (invalid Observation -> OperationOutcome).
- Slide 4: Demo 2: Inyección masiva (inject.sh) y resultados.
- Slide 5: Demo 3: Rate limiting (mostrar 429 en respuestas & logs).
- Slide 6: Conclusiones y recomendaciones.

11. Recursos adicionales
------------------------
- Documentación Kong: https://docs.konghq.com
- HAPI FHIR: https://hapifhir.io
- FHIR R4 spec: https://www.hl7.org/fhir/

Usa este `LAB_PRESENTATION.md` como guión para presentar el laboratorio o como notas para un taller. Ajusta tiempos y comandos según la audiencia y el entorno.
