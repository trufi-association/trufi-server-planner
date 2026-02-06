#!/bin/bash
set -e

echo "==================================="
echo "🧪 Trufi Server Integration Tests"
echo "==================================="
echo ""

# Check if server is running
echo "Checking if server is running on port 9090..."
if ! curl -s http://localhost:9090/health > /dev/null 2>&1; then
    echo "❌ Server is not running on port 9090"
    echo ""
    echo "Please start the server first:"
    echo "  Option 1: docker-compose up -d"
    echo "  Option 2: PORT=9090 dart run bin/server.dart"
    echo ""
    exit 1
fi

echo "✓ Server is running"
echo ""

# Run integration tests
echo "Running integration tests..."
echo ""
dart test test/integration_test.dart

echo ""
echo "==================================="
echo "✅ All tests passed!"
echo "==================================="
