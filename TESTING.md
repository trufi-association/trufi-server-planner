# Testing Guide

## Integration Tests

El servidor incluye tests de integración completos que verifican todos los endpoints.

### Prerequisitos

1. El servidor debe estar corriendo en el puerto **9090**
2. Dart SDK instalado

### Ejecutar Tests

#### Opción 1: Script Automático (Recomendado)

```bash
./run_tests.sh
```

#### Opción 2: Manual

```bash
# Iniciar el servidor
PORT=9090 dart run bin/server.dart

# En otra terminal, ejecutar tests
dart test test/integration_test.dart
```

#### Opción 3: Con Docker Compose

```bash
# Iniciar servidor con docker-compose
docker-compose up -d

# Esperar a que inicie (15-20 segundos)
sleep 20

# Ejecutar tests
./run_tests.sh

# Detener servidor
docker-compose down
```

## Tests Incluidos

Los integration tests verifican:

### ✅ 1. Health Check
- Verifica que el servidor está saludable
- Comprueba que los datos GTFS están cargados
- Valida conteo de stops, routes y trips

### ✅ 2. List Stops
- Lista paradas con límite
- Verifica estructura de datos de paradas
- Valida campos requeridos (id, name, lat, lon)

### ✅ 3. Nearby Stops
- Busca paradas cercanas a coordenadas
- Verifica distancias calculadas
- Valida radio de búsqueda (500m)

### ✅ 4. List Routes
- Lista todas las rutas disponibles
- Verifica estructura de datos de rutas
- Valida campos (shortName, longName)

### ✅ 5. Plan Route
- Planifica ruta entre dos puntos
- Verifica paths encontrados
- Valida estructura completa (segments, walks, transfers)
- Comprueba datos de rutas y paradas

### ✅ 6. Error Handling
- Verifica manejo de requests inválidos
- Comprueba códigos de error HTTP
- Valida mensajes de error

### ✅ 7. Web App
- Verifica que el HTML se sirve correctamente
- Comprueba content-type

### ✅ 8. CORS
- Verifica headers CORS para acceso web
- Comprueba Access-Control-Allow-Origin

## Output Esperado

```
00:00 +0: Trufi Server Planner Integration Tests Health check returns status and GTFS data
✓ Health check passed
  - 8121 stops
  - 134 routes
  - 438 trips
00:00 +1: Trufi Server Planner Integration Tests List stops returns data
✓ List stops passed
  - Found 5 stops
00:00 +2: Trufi Server Planner Integration Tests Find nearby stops works
✓ Nearby stops passed
  - Found 5 stops within 500m
  - Closest: Avenida Heroínas de la Coronilla at 139.0m
00:00 +3: Trufi Server Planner Integration Tests List routes returns data
✓ List routes passed
  - Found 134 routes
  - First route: 270 - MiniBus 270: Tupuraya → Avenida Blanco Galindo
00:00 +4: Trufi Server Planner Integration Tests Plan route finds paths
✓ Plan route passed
  - Found 5 paths
  - First route: 36 (17 stops)
  - Walk: 180.0m + 236.0m = 416.0m
  - Transfers: 0
00:00 +5: Trufi Server Planner Integration Tests Plan route handles missing coordinates
✓ Error handling passed
  - Correctly rejects invalid input
00:00 +6: Trufi Server Planner Integration Tests Web app serves HTML
✓ Web app passed
  - HTML page served correctly
00:00 +7: Trufi Server Planner Integration Tests CORS headers are present
✓ CORS passed
  - CORS headers present
00:00 +8: All tests passed!
```

## Comandos curl para Testing Manual

### Health Check
```bash
curl http://localhost:9090/health | jq
```

### Nearby Stops
```bash
curl "http://localhost:9090/stops/nearby?lat=-17.3935&lon=-66.1570&maxResults=5" | jq
```

### Plan Route
```bash
curl -X POST http://localhost:9090/plan \
  -H "Content-Type: application/json" \
  -d '{"from":{"lat":-17.3935,"lon":-66.1570},"to":{"lat":-17.4000,"lon":-66.1600}}' \
  | jq
```

## CI/CD Integration

Para integrar en CI/CD:

```yaml
# GitHub Actions example
- name: Run Integration Tests
  run: |
    docker-compose up -d
    sleep 20
    ./run_tests.sh
    docker-compose down
```

## Troubleshooting

### Server not running
```bash
❌ Server is not running on port 9090
```
**Solución**: Inicia el servidor primero con `docker-compose up -d` o `PORT=9090 dart run bin/server.dart`

### Connection refused
**Solución**: Verifica que el puerto 9090 no esté en uso por otro proceso

### Tests failing
**Solución**:
1. Verifica que el GTFS data está cargado
2. Comprueba los logs del servidor: `docker-compose logs -f`
3. Prueba los endpoints manualmente con curl
