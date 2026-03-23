#!/bin/bash

# Comprehensive test runner for all components
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TESTS=(
    "test_kafka.sh"
    "test_redis.sh"
    "test_api.sh"
    "test_consumer.sh"
    "test_prometheus.sh"
    "test_grafana.sh"
)

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Thinklabs MLOps Orchestrator - Comprehensive Test Suite   ║"
echo "╚════════════════════════════════════════════════════════════╝"

passed=0
failed=0

for test in "${TESTS[@]}"; do
    test_path="$SCRIPT_DIR/$test"
    
    if [ ! -f "$test_path" ]; then
        echo "❌ Test script not found: $test_path"
        ((failed++))
        continue
    fi
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║ Running: $test"
    echo "╚════════════════════════════════════════════════════════════╝"
    
    if bash "$test_path"; then
        echo ""
        echo "✅ $test PASSED"
        ((passed++))
    else
        echo ""
        echo "❌ $test FAILED"
        ((failed++))
    fi
done

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║ Test Summary"
echo "╚════════════════════════════════════════════════════════════╝"
echo "Passed: $passed"
echo "Failed: $failed"
echo "Total:  $((passed + failed))"

if [ $failed -gt 0 ]; then
    exit 1
else
    echo ""
    echo "✅ All tests passed!"
    exit 0
fi
