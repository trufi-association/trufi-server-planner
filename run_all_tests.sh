#!/bin/bash
set -e

echo "========================================="
echo "🧪 Trufi Server - Complete Test Suite"
echo "========================================="
echo ""

# Check if server is running
echo "Checking if server is running on port 9090..."
if ! curl -s http://localhost:9090/health > /dev/null 2>&1; then
    echo "❌ Server is not running on port 9090"
    echo ""
    echo "Please start the server first:"
    echo "  docker-compose up -d"
    echo "  OR"
    echo "  PORT=9090 dart run bin/server.dart"
    echo ""
    exit 1
fi

echo "✓ Server is running"
echo ""

# Run all test suites
echo "========================================="
echo "📋 Test Suite 1: Integration Tests"
echo "========================================="
dart test test/integration_test.dart
echo ""

echo "========================================="
echo "🗺️  Test Suite 2: Routing Scenarios"
echo "========================================="
dart test test/routing_scenarios_test.dart
echo ""

echo "========================================="
echo "⚡ Test Suite 3: Performance Tests"
echo "========================================="
dart test test/performance_test.dart
echo ""

echo "========================================="
echo "✅ Test Suite 4: Data Validation"
echo "========================================="
dart test test/data_validation_test.dart
echo ""

echo "========================================="
echo "🎉 All Test Suites Completed!"
echo "========================================="
echo ""
echo "Summary:"
echo "  ✅ Integration tests (8 tests)"
echo "  ✅ Routing scenarios (8 plans)"
echo "  ✅ Performance tests (7 tests)"
echo "  ✅ Data validation (8 tests)"
echo "  Total: 31 tests"
echo ""
