# Test Plans - Trufi Server Planner

Documentación completa de todos los planes de prueba del servidor.

## 🎯 Resumen

| Test Suite | Tests | Descripción |
|------------|-------|-------------|
| Integration | 8 | Tests básicos de endpoints |
| Routing Scenarios | 8 | Planes de routing en diferentes escenarios |
| Performance | 7 | Tests de rendimiento y concurrencia |
| Data Validation | 8 | Validación de estructura de datos |
| **TOTAL** | **31** | **Tests completos** |

## 📋 Test Suite 1: Integration Tests

### Tests Incluidos:
1. ✅ **Health Check** - Verifica estado del servidor
2. ✅ **List Stops** - Lista paradas con paginación
3. ✅ **Find Nearby Stops** - Búsqueda espacial
4. ✅ **List Routes** - Lista todas las rutas
5. ✅ **Plan Route** - Routing completo
6. ✅ **Error Handling** - Manejo de errores
7. ✅ **Web App** - Archivos estáticos
8. ✅ **CORS** - Headers CORS

**Ejecutar:**
```bash
dart test test/integration_test.dart
```

## 🗺️ Test Suite 2: Routing Scenarios

### Plan 1: Centro to Zona Sur
**Origen:** Centro (-17.3935, -66.1570)
**Destino:** Zona Sur (-17.4200, -66.1650)
**Objetivo:** Validar rutas sur del centro

### Plan 2: Plaza 14 de Septiembre to Universidad
**Origen:** Plaza (-17.3895, -66.1568)
**Destino:** Zona Universidad (-17.3700, -66.1500)
**Objetivo:** Validar rutas norte de la ciudad

### Plan 3: Short Distance (~200m)
**Origen:** Centro (-17.3935, -66.1570)
**Destino:** Cerca (-17.3945, -66.1580)
**Objetivo:** Validar que distancias cortas prefieren caminar

### Plan 4: Avenida Blanco Galindo Corridor
**Origen:** (-17.3900, -66.2000)
**Destino:** (-17.3950, -66.1800)
**Objetivo:** Validar corredor principal de alto tránsito

### Plan 5: North to Center
**Origen:** Norte (-17.3700, -66.1600)
**Destino:** Centro (-17.3935, -66.1570)
**Objetivo:** Validar rutas hacia el centro

### Plan 6: Multiple Route Options
**Origen:** Centro (-17.3935, -66.1570)
**Destino:** Norte (-17.4000, -66.1600)
**Objetivo:** Comparar múltiples opciones de ruta

### Plan 7: Very Long Distance (~15km)
**Origen:** (-17.3500, -66.1000)
**Destino:** (-17.4500, -66.2000)
**Objetivo:** Edge case - distancias muy largas

### Plan 8: Same Location
**Origen:** Centro (-17.3935, -66.1570)
**Destino:** Centro (-17.3935, -66.1570)
**Objetivo:** Edge case - mismo origen y destino

**Ejecutar:**
```bash
dart test test/routing_scenarios_test.dart
```

## ⚡ Test Suite 3: Performance Tests

### Tests de Rendimiento:

1. **Health Check Response Time**
   - Target: < 1 segundo
   - Valida tiempo de respuesta básico

2. **Nearby Stops Search Performance**
   - Target: < 500ms
   - Valida búsqueda espacial eficiente

3. **Route Planning Performance**
   - Target: < 3 segundos
   - Valida algoritmo de routing

4. **Concurrent Requests (10)**
   - Target: < 2 segundos total
   - Valida manejo concurrente

5. **List All Routes Performance**
   - Target: < 500ms
   - Valida queries de lista

6. **Sequential Planning (5 requests)**
   - Valida consistencia en múltiples requests

7. **Large Result Sets (1000 stops)**
   - Valida eficiencia de memoria

**Ejecutar:**
```bash
dart test test/performance_test.dart
```

## ✅ Test Suite 4: Data Validation

### Validaciones de Datos:

1. **Stop Data Structure**
   - Campos requeridos (id, name, lat, lon)
   - Rangos de coordenadas válidos (Cochabamba)

2. **Route Data Structure**
   - Campos requeridos
   - Tipos GTFS válidos (0-12)

3. **Path Data Structure**
   - Estructura completa de paths
   - Segments válidos
   - Cálculos correctos

4. **Distance Calculations**
   - Distancias dentro del radio
   - Orden ascendente correcto

5. **Route Scoring Consistency**
   - Scores en orden ascendente
   - Algoritmo consistente

6. **HTTP Headers**
   - Content-Type correcto
   - CORS habilitado

7. **JSON Response Format**
   - JSON válido en todos los endpoints

8. **Error Response Format**
   - Errores bien formateados
   - Mensajes informativos

**Ejecutar:**
```bash
dart test test/data_validation_test.dart
```

## 🚀 Ejecutar Todos los Tests

### Opción 1: Script Completo
```bash
./run_all_tests.sh
```

### Opción 2: Manual
```bash
# Iniciar servidor
docker-compose up -d
sleep 20

# Ejecutar todos
dart test test/integration_test.dart
dart test test/routing_scenarios_test.dart
dart test test/performance_test.dart
dart test test/data_validation_test.dart

# Detener
docker-compose down
```

### Opción 3: Un Solo Comando
```bash
dart test
```

## 📊 Output Esperado

```
========================================
🧪 Test Suite 1: Integration Tests
========================================
00:00 +8: All tests passed!

========================================
🗺️  Test Suite 2: Routing Scenarios
========================================
✓ Plan 1: Centro → Zona Sur - Found 3 routes
✓ Plan 2: Plaza → Universidad - Found 5 routes
✓ Plan 3: Short distance - No transit routes
✓ Plan 4: Blanco Galindo corridor - Found 7 routes
✓ Plan 5: North → Center - Found 4 routes
✓ Plan 6: Multiple options - Comparing 5 routes
✓ Plan 7: Very long distance - No routes
✓ Plan 8: Same location - No route needed
00:00 +8: All tests passed!

========================================
⚡ Test Suite 3: Performance Tests
========================================
✓ Health check: 45ms
✓ Nearby stops: 123ms (5 results)
✓ Route planning: 856ms (5 routes)
✓ Concurrent requests (10): 567ms
✓ List routes: 89ms (134 routes)
✓ Sequential planning: 4231ms
✓ Large result set: 1000 stops
00:00 +7: All tests passed!

========================================
✅ Test Suite 4: Data Validation
========================================
✓ Stop data structure valid
✓ Route data structure valid
✓ Path data structure valid
✓ Distance calculations accurate
✓ Route scoring consistent
✓ HTTP headers valid
✓ All endpoints return valid JSON
✓ Error responses properly formatted
00:00 +8: All tests passed!

========================================
🎉 Total: 31 tests passed!
========================================
```

## 🔍 Debugging Tests

Si un test falla:

1. **Verificar el servidor:**
   ```bash
   curl http://localhost:9090/health
   ```

2. **Ver logs del servidor:**
   ```bash
   docker-compose logs -f planner
   ```

3. **Ejecutar un test individual:**
   ```bash
   dart test test/integration_test.dart --name "Health check"
   ```

4. **Modo verbose:**
   ```bash
   dart test test/integration_test.dart --reporter expanded
   ```

## 📈 Métricas de Éxito

- ✅ **Coverage**: 100% de endpoints probados
- ✅ **Performance**: Todos los targets cumplidos
- ✅ **Reliability**: 0% de tests flaky
- ✅ **Data Integrity**: Todas las validaciones pasan

## 🔄 CI/CD Integration

Los tests están configurados para GitHub Actions en `.github/workflows/test.yml`.

Cada push ejecuta automáticamente todos los tests.
