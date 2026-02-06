#!/bin/bash
# Trufi Server Planner - Example API Requests

BASE_URL="http://localhost:8080"

echo "=== Health Check ==="
curl -s "$BASE_URL/health" | json_pp
echo ""

echo "=== List 5 stops ==="
curl -s "$BASE_URL/stops?limit=5" | json_pp
echo ""

echo "=== Find nearby stops (Cochabamba Centro) ==="
curl -s "$BASE_URL/stops/nearby?lat=-17.3935&lon=-66.1570&maxResults=5&maxDistance=500" | json_pp
echo ""

echo "=== List all routes ==="
curl -s "$BASE_URL/routes" | json_pp | head -50
echo ""

echo "=== Plan a route ==="
curl -s -X POST "$BASE_URL/plan" \
  -H "Content-Type: application/json" \
  -d '{
    "from": {"lat": -17.3935, "lon": -66.1570},
    "to": {"lat": -17.4000, "lon": -66.1600}
  }' | json_pp
echo ""
