import 'dart:convert';

import 'package:shelf/shelf.dart';

Response swaggerUiHandler(Request request) {
  return Response.ok(
    '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Trufi Planner API</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    SwaggerUIBundle({ url: '/api/openapi.json', dom_id: '#swagger-ui' });
  </script>
</body>
</html>''',
    headers: {'Content-Type': 'text/html'},
  );
}

Response openApiSpecHandler(Request request) {
  return Response.ok(
    jsonEncode(_openApiSpec),
    headers: {'Content-Type': 'application/json'},
  );
}

const _openApiSpec = {
  'openapi': '3.0.3',
  'info': {
    'title': 'Trufi Server Planner API',
    'description': 'GTFS-based transit routing API for Cochabamba, Bolivia',
    'version': '1.0.0',
  },
  'servers': [
    {'url': '/api', 'description': 'API'},
  ],
  'paths': {
    '/health': {
      'get': {
        'summary': 'Health check',
        'tags': ['System'],
        'responses': {
          '200': {
            'description': 'Server status and GTFS data summary',
            'content': {
              'application/json': {
                'schema': {
                  'type': 'object',
                  'properties': {
                    'status': {'type': 'string'},
                    'service': {'type': 'string'},
                    'gtfs': {
                      'type': 'object',
                      'properties': {
                        'stops': {'type': 'integer'},
                        'routes': {'type': 'integer'},
                        'trips': {'type': 'integer'},
                        'shapes': {'type': 'integer'},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
    '/stops': {
      'get': {
        'summary': 'List stops',
        'tags': ['Stops'],
        'parameters': [
          {
            'name': 'limit',
            'in': 'query',
            'schema': {'type': 'integer', 'default': 100},
            'description': 'Max number of stops to return',
          },
        ],
        'responses': {
          '200': {
            'description': 'List of stops',
            'content': {
              'application/json': {
                'schema': {
                  'type': 'object',
                  'properties': {
                    'stops': {
                      'type': 'array',
                      'items': {r'$ref': '#/components/schemas/Stop'},
                    },
                    'total': {'type': 'integer'},
                  },
                },
              },
            },
          },
        },
      },
    },
    '/stops/nearby': {
      'get': {
        'summary': 'Find nearby stops',
        'tags': ['Stops'],
        'parameters': [
          {
            'name': 'lat',
            'in': 'query',
            'required': true,
            'schema': {'type': 'number'},
            'description': 'Latitude',
          },
          {
            'name': 'lon',
            'in': 'query',
            'required': true,
            'schema': {'type': 'number'},
            'description': 'Longitude',
          },
          {
            'name': 'maxDistance',
            'in': 'query',
            'schema': {'type': 'number', 'default': 500},
            'description': 'Max distance in meters',
          },
          {
            'name': 'maxResults',
            'in': 'query',
            'schema': {'type': 'integer', 'default': 10},
            'description': 'Max number of results',
          },
        ],
        'responses': {
          '200': {
            'description': 'Nearby stops with distances',
          },
        },
      },
    },
    '/routes': {
      'get': {
        'summary': 'List all transit routes',
        'tags': ['Routes'],
        'responses': {
          '200': {
            'description': 'List of routes',
            'content': {
              'application/json': {
                'schema': {
                  'type': 'object',
                  'properties': {
                    'routes': {
                      'type': 'array',
                      'items': {r'$ref': '#/components/schemas/Route'},
                    },
                    'total': {'type': 'integer'},
                  },
                },
              },
            },
          },
        },
      },
    },
    '/routes/{id}': {
      'get': {
        'summary': 'Get route detail with geometry and stops',
        'tags': ['Routes'],
        'parameters': [
          {
            'name': 'id',
            'in': 'path',
            'required': true,
            'schema': {'type': 'string'},
            'description': 'Route ID',
          },
        ],
        'responses': {
          '200': {
            'description': 'Route detail with geometry and stops',
          },
          '404': {
            'description': 'Route not found',
          },
        },
      },
    },
    '/plan': {
      'post': {
        'summary': 'Plan a transit route between two points',
        'tags': ['Routing'],
        'requestBody': {
          'required': true,
          'content': {
            'application/json': {
              'schema': {
                'type': 'object',
                'required': ['from', 'to'],
                'properties': {
                  'from': {
                    'type': 'object',
                    'required': ['lat', 'lon'],
                    'properties': {
                      'lat': {'type': 'number', 'example': -17.420536},
                      'lon': {'type': 'number', 'example': -66.143176},
                    },
                  },
                  'to': {
                    'type': 'object',
                    'required': ['lat', 'lon'],
                    'properties': {
                      'lat': {'type': 'number', 'example': -17.384842},
                      'lon': {'type': 'number', 'example': -66.147902},
                    },
                  },
                  'maxResults': {
                    'type': 'integer',
                    'description':
                        'Maximum paths to return (1-20; values outside '
                        'the range are clamped). Defaults to 20.',
                    'example': 20,
                  },
                  'maxWalkDistance': {
                    'type': 'number',
                    'description':
                        'Walk radius to board/alight, in meters '
                        '(100-2000; values outside the range are '
                        'clamped). Defaults to 800.',
                    'example': 800,
                  },
                  'maxStopCandidates': {
                    'type': 'integer',
                    'description':
                        'Stops considered around the origin and the '
                        'destination, nearest first within '
                        'maxWalkDistance (1-600; higher values are '
                        'capped). Defaults to 150, the planner default.',
                    'example': 150,
                  },
                  'maxTransfers': {
                    'type': 'integer',
                    'description':
                        'Most bus changes an itinerary may have (0-5; '
                        'higher values are capped). 0 returns direct '
                        'lines only. Defaults to 1.',
                    'example': 1,
                  },
                  'directsHideTransfers': {
                    'type': 'boolean',
                    'description':
                        'Whether a direct line hides the one-transfer '
                        'options (trufi-core#1043). Defaults to true; '
                        'false lists the one-transfer itineraries after '
                        'the direct ones, nothing extra is searched.',
                    'example': true,
                  },
                },
              },
            },
          },
        },
        'responses': {
          '200': {
            'description':
                'Routing results with transit paths. effectiveParameters '
                'reports the values the search actually ran with, after '
                'defaults and caps; ignoredParameters, present only when '
                'needed, names the fields received that the pinned '
                'planner cannot honour (none since trufi_core_planner '
                'v5.28.0).',
          },
          '400': {
            'description':
                'Missing from/to coordinates; a field of the wrong type '
                '(maxResults/maxWalkDistance not a number, '
                'maxStopCandidates/maxTransfers not an integer, '
                'directsHideTransfers not a boolean); or '
                'maxStopCandidates/maxTransfers below the floor. The '
                'first offending field, in the order above, is reported: '
                '{"error": "maxTransfers must be >= 0"}.',
          },
        },
      },
    },
  },
  'components': {
    'schemas': {
      'Stop': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'name': {'type': 'string'},
          'lat': {'type': 'number'},
          'lon': {'type': 'number'},
        },
      },
      'Route': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'agencyId': {'type': 'string'},
          'shortName': {'type': 'string'},
          'longName': {'type': 'string'},
          'type': {'type': 'string'},
          'color': {'type': 'string', 'nullable': true},
          'textColor': {'type': 'string', 'nullable': true},
        },
      },
    },
  },
};
