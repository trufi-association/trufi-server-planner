# Trufi Server Planner

Servidor de routing offline usando datos GTFS para aplicaciones Trufi.

## Descripción

Este servidor expone el routing GTFS offline como servicio HTTP, permitiendo que la versión web de trufi-app pueda usar routing sin necesidad de assets locales.

Similar a [trufi-server-photon](../trufi-server-photon) pero para planificación de rutas en lugar de geocoding.

**El servidor sirve dos cosas:**
1. 🌐 **Web App**: Archivos estáticos de la aplicación Flutter web (trufi-app)
2. 🔌 **API REST**: Endpoints de routing para consultar rutas, paradas, etc.

## Características

- 🌐 **Web App Incluida**: Sirve la aplicación Flutter web como archivos estáticos
- 🚌 **Routing Offline**: Usa datos GTFS locales sin conexión a internet
- 🔍 **Búsqueda de paradas**: Encuentra paradas cercanas a coordenadas
- 🗺️ **Planificación de rutas**: Calcula rutas entre dos puntos
- 📍 **Índice espacial**: Búsqueda rápida de paradas cercanas (KD-Tree)
- 🐳 **Docker**: Fácil despliegue con Docker Compose
- 🔌 **API REST**: Endpoints HTTP simples y documentados
- 📦 **Código compartido**: Usa `trufi_core_planner` (mismo algoritmo que trufi-app)

## Arquitectura

Este servidor utiliza **`trufi_core_planner`**, un paquete compartido que contiene la lógica central de parsing GTFS y routing. Esto garantiza que el algoritmo de routing sea **idéntico** en:

- 📱 **trufi-app** (Flutter mobile/web) → usa `trufi_core_routing` → usa `trufi_core_planner`
- 🖥️ **trufi-server-planner** (servidor Dart) → usa `trufi_core_planner` directamente

**Ventajas:**
- ✅ No hay duplicación de código
- ✅ El mismo GTFS produce las mismas rutas en web y móvil
- ✅ Los bugs se corrigen una vez para todos
- ✅ Más fácil de mantener y probar

Ver [MIGRATION.md](../trufi-core/packages/trufi_core_planner/MIGRATION.md) para más detalles.

## Requisitos

- Docker y Docker Compose, O
- Dart SDK 3.10+ (para desarrollo local)

## Quick Start

### 1. Preparar Web App (Opcional)

Por defecto, el servidor incluye una página placeholder. Para usar la app real de Flutter:

```bash
# Opción A: Script automático
./copy_flutter_build.sh

# Opción B: Manual
cd ../trufi-app
flutter build web --release
cd ../trufi-server-planner
cp -r ../trufi-app/build/web/* web/
```

### 2. Con Docker (Recomendado)

```bash
# Construir e iniciar el servidor
docker-compose up -d --build

# Ver logs
docker-compose logs -f planner

# Acceder a:
# - Web App: http://localhost:8080/
# - API: http://localhost:8080/health
```

### 3. Desarrollo Local

```bash
# Instalar dependencias
dart pub get

# Ejecutar el servidor
dart run bin/server.dart

# O compilar y ejecutar
dart compile exe bin/server.dart -o build/server
./build/server
```

## API Endpoints

### Health Check
```bash
GET /health

# Respuesta
{
  "status": "healthy",
  "service": "trufi-server-planner",
  "gtfs": {
    "stops": 1234,
    "routes": 56,
    "trips": 789
  }
}
```

### Listar Paradas
```bash
GET /stops?limit=100

# Respuesta
{
  "stops": [
    {
      "id": "stop_1",
      "name": "Parada Central",
      "lat": -17.3935,
      "lon": -66.1570,
      "code": "001"
    }
  ],
  "total": 1234
}
```

### Paradas Cercanas
```bash
GET /stops/nearby?lat=-17.3935&lon=-66.1570&maxDistance=500&maxResults=10

# Parámetros:
# - lat: Latitud (requerido)
# - lon: Longitud (requerido)
# - maxDistance: Distancia máxima en metros (default: 500)
# - maxResults: Número máximo de resultados (default: 10)

# Respuesta
{
  "stops": [
    {
      "stop": {
        "id": "stop_1",
        "name": "Parada Central",
        "lat": -17.3935,
        "lon": -66.1570
      },
      "distance": 123.45
    }
  ],
  "count": 5
}
```

### Listar Rutas
```bash
GET /routes

# Respuesta
{
  "routes": [
    {
      "id": "route_1",
      "shortName": "1",
      "longName": "Centro - Norte",
      "type": "3",
      "color": "FF0000"
    }
  ],
  "total": 56
}
```

### Planificar Ruta
```bash
POST /plan
Content-Type: application/json

{
  "from": {
    "lat": -17.3935,
    "lon": -66.1570
  },
  "to": {
    "lat": -17.4000,
    "lon": -66.1600
  },
  "time": "2024-02-06T10:00:00Z" // opcional
}

# Respuesta
{
  "success": true,
  "itineraries": [
    {
      "legs": [
        {
          "mode": "WALK",
          "to": { "id": "stop_1", "name": "Parada A" },
          "duration": 120
        },
        {
          "mode": "TRANSIT",
          "from": { "id": "stop_1", "name": "Parada A" },
          "to": { "id": "stop_2", "name": "Parada B" },
          "route": {
            "id": "route_1",
            "shortName": "1",
            "longName": "Centro - Norte"
          },
          "duration": 600
        },
        {
          "mode": "WALK",
          "from": { "id": "stop_2", "name": "Parada B" },
          "duration": 90
        }
      ],
      "duration": 810
    }
  ]
}
```

#### Parámetros opcionales de `/plan`

| Campo | Tipo | Rango | Default |
|---|---|---|---|
| `maxResults` | entero | 1–20 (por encima se recorta) | 20 |
| `maxWalkDistance` | número | 100–2000 m (por encima se recorta) | 800 |
| `maxStopCandidates` | entero | 1–600 (por encima se recorta) | 150 |
| `maxTransfers` | entero | 0–5 (por encima se recorta) | 1 |
| `directsHideTransfers` | booleano | — | `true` |

Son los campos que manda el `RemotePlannerClient` de trufi-core (`TrufiPlannerConfig.remote`; `maxStopCandidates` desde trufi-core#934, `maxTransfers` desde #998/#999, `directsHideTransfers` desde #1043). Ausente o `null` usa el default. Un valor de tipo incorrecto responde `400` con `{"error": "<campo> must be a number | an integer | a boolean"}`: `maxResults` y `maxWalkDistance` aceptan cualquier número JSON finito y se recortan al rango por ambos lados (`0` → 1, `2.7` → 2, `5000` → 2000); `maxStopCandidates` y `maxTransfers` solo aceptan enteros (`150.0` cuenta como entero), por debajo del mínimo responden `400` (`must be >= 1` / `must be >= 0`) y por encima del tope se recortan. Si hay varios campos inválidos se reporta el primero en el orden de la tabla (las coordenadas ausentes van antes que todo). La respuesta (con o sin rutas) incluye `effectiveParameters`: los valores con los que corrió la búsqueda, tras defaults y recortes. Cuando un campo recibido no coincide con lo que corrió, la respuesta añade `ignoredParameters` con sus nombres. Hoy eso pasa con `directsHideTransfers: false`: el `trufi_core_planner` fijado en `pubspec.yaml` (v5.27.0) no tiene el parámetro (llega con trufi-core#1043), así que la búsqueda corre siempre con `true`, `effectiveParameters` lo reporta así e `ignoredParameters` lo lista.

## Configuración

### Variables de Entorno

- `PORT`: puerto del servidor (default: `8080`).
- `GTFS_FILE`: ruta del archivo GTFS dentro del proceso (default: `data/gtfs.zip`).

### Archivo GTFS

El servidor lee el feed desde `data/gtfs.zip` (relativo al cwd del proceso, o `/app/data/gtfs.zip` en docker). El directorio `data/` está gitignoreado: cada deploy/dev pone su propio feed allí.

Para cambiar los datos:

```bash
# Generá el feed con el builder (una vez):
cd ../trufi-app/tools/gtfs-bolivia-cochabamba
npm install && npm start

# Copialo:
cp ../trufi-app/tools/gtfs-bolivia-cochabamba/out/cochabamba.gtfs.zip data/gtfs.zip

# Reiniciá el contenedor:
docker-compose restart planner
```

El repo incluye `example.gtfs.zip` (3.6MB, Cochabamba) como feed de referencia para tests/dev. CI lo copia a `data/gtfs.zip` antes de correr los integration tests.

## Integración con trufi-server

Similar a trufi-server-photon, este servicio se puede integrar con [trufi-server](https://github.com/trufi-association/trufi-server):

### docker-compose.yml
```yaml
services:
  planner:
    build:
      context: ./trufi-server-planner
    restart: unless-stopped
    mem_limit: 2g
    networks:
      - trufi-server
```

### Configuración en trufi-server
```json
{
  "ReverseProxy": {
    "Routes": {
      "planner": {
        "ClusterId": "planner",
        "Match": {
          "Hosts": ["planner.yourdomain.com"]
        }
      }
    },
    "Clusters": {
      "planner": {
        "Destinations": {
          "planner": {
            "Address": "http://planner:8080"
          }
        }
      }
    }
  }
}
```

## Estructura del Proyecto

```
trufi-server-planner/
├── bin/
│   └── server.dart              # Servidor HTTP principal
├── lib/src/
│   ├── models/                  # Modelos GTFS
│   │   ├── gtfs_stop.dart
│   │   ├── gtfs_route.dart
│   │   ├── gtfs_trip.dart
│   │   └── gtfs_stop_time.dart
│   ├── parser/                  # Parser GTFS
│   │   └── gtfs_parser.dart
│   ├── index/                   # Índices para búsqueda
│   │   └── spatial_index.dart
│   └── routing/                 # Motor de routing
│       └── simple_planner.dart
├── gtfs_data.zip                # Datos GTFS (Cochabamba)
├── Dockerfile                   # Imagen Docker
├── docker-compose.yml           # Orquestación
└── pubspec.yaml                 # Dependencias Dart
```

## Desarrollo

### Agregar funcionalidades

El planner actual es básico. Puedes mejorarlo:

1. **Algoritmo de routing**: Implementar A* o Dijkstra para rutas óptimas
2. **Horarios**: Usar `stop_times.txt` para horarios reales
3. **Transferencias**: Soportar múltiples transferencias
4. **Modos**: Agregar caminata, bicicleta, etc.
5. **Tiempo real**: Integrar con GTFS-RT

### Tests

```bash
dart test
```

## Troubleshooting

### El servidor no inicia
```bash
# Ver logs
docker-compose logs planner

# Verificar que gtfs_data.zip existe
ls -lh gtfs_data.zip
```

### Errores de memoria
Si el GTFS es muy grande, aumenta el límite de memoria en `docker-compose.yml`:
```yaml
mem_limit: 4g  # En lugar de 2g
```

### Recargar datos GTFS
```bash
# Copiar nuevo archivo
cp nuevo_gtfs.zip gtfs_data.zip

# Reiniciar contenedor
docker-compose restart planner
```

## Datos GTFS

El servidor actualmente usa datos GTFS de Cochabamba, Bolivia (`input/cochabamba.gtfs.zip`).

Para usar datos de otra ciudad, simplemente reemplaza `gtfs_data.zip` con tu archivo GTFS.

## Créditos

- [Trufi Association](https://trufi-association.org) - Open source transit tools for the Global South
- [GTFS Specification](https://gtfs.org/) - General Transit Feed Specification
- [OpenTripPlanner](https://www.opentripplanner.org/) - Inspiración para el routing

## License

Part of the Trufi server stack. Open source para mejorar el transporte público en el Sur Global.
