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

## Configuración

### Variables de Entorno

- `PORT`: puerto del servidor (default: `8080`).
- `GTFS_FILE`: ruta del archivo GTFS dentro del proceso (default: `data/gtfs.zip`).

### Compresión y caché de la web

Los archivos de `web/` salen con `Content-Encoding: gzip` cuando el cliente manda `Accept-Encoding: gzip` (`main.dart.js` 5,0 MB → 1,4 MB; `search.json` 1,4 MB → 0,36 MB). Los tipos ya comprimidos (PNG, WOFF2, ZIP…), los cuerpos de menos de 512 bytes, los `304`, los `HEAD` y las respuestas parciales (`Range`) van tal cual; `/api/*` no se toca.

`Cache-Control`: `no-cache` para todo el build (Flutter no pone hash en los nombres, así que el navegador guarda los bytes pero revalida con `ETag`/`Last-Modified` y recibe `304`), y `public, max-age=31536000, immutable` para nombres con hash de contenido (`main.dart.<hash>.js`, lo que produce `flutter build web --web-content-hash`). Lógica y tests: `lib/web_app.dart`, `test/web_app_test.dart`.

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
