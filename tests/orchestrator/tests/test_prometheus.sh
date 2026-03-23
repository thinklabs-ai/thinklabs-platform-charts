#!/bin/bash

# Test script for Prometheus Monitoring
set -e

echo "=== Testing Prometheus ==="

# Port forward to Prometheus
echo ""
echo "Setting up port-forward to Prometheus..."
kubectl port-forward -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0 9090:9090 &
PF_PID=$!
sleep 4

trap "kill $PF_PID 2>/dev/null" EXIT

PROM_URL="http://localhost:9090"

# Check Prometheus health
echo ""
echo "=== Checking Prometheus Health ==="
response=$(curl -s -w "\n%{http_code}" -X GET "$PROM_URL/-/healthy")
http_code=$(echo "$response" | tail -n1)

if [ "$http_code" = "200" ]; then
    echo "✅ Prometheus is healthy"
else
    echo "❌ Prometheus health check failed (HTTP $http_code)"
fi

# Test API endpoint
echo ""
echo "=== Testing Prometheus API ==="
response=$(curl -s "$PROM_URL/api/v1/query?query=up")
status=$(echo "$response" | jq -r '.status' 2>/dev/null || echo "failed")

if [ "$status" = "success" ]; then
    echo "✅ Prometheus API is responding correctly"
else
    echo "⚠️  Prometheus API returned: $status (may still be working)"
fi

# List available metrics from orchestrator-api
echo ""
echo "=== Querying Orchestrator API Metrics ==="
echo "Available metrics from orchestrator-api:"

# Query for orchestrator metrics
queries=(
    "orchestrator_http_requests_total"
    "orchestrator_http_request_duration_seconds"
)

for query in "${queries[@]}"; do
    echo ""
    echo "Query: $query"
    response=$(curl -s -X GET "$PROM_URL/api/v1/query" --data-urlencode "query=$query")
    result=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    
    if [ "$result" -gt "0" ]; then
        echo "✅ Metric found with $result time series"
        echo "$response" | jq '.data.result[] | {metric: .metric, value: .value}' 2>/dev/null | head -20
    else
        echo "⚠️  No data available for metric yet (expected if API just started)"
    fi
done

# Check uptime of orchestrator-api pods
echo ""
echo "=== Checking Pod Uptime ==="
echo "Query: up{job='orchestrator-api'}"
response=$(curl -s -X GET "$PROM_URL/api/v1/query" --data-urlencode 'query=up{job="orchestrator-api"}')
echo "$response" | jq '.data.result[]' 2>/dev/null || echo "No results"

# Check targets
echo ""
echo "=== Checking Prometheus Targets ==="
response=$(curl -s -X GET "$PROM_URL/api/v1/targets")
active=$(echo "$response" | jq '.data.activeTargets | length' 2>/dev/null || echo "0")
dropped=$(echo "$response" | jq '.data.droppedTargets | length' 2>/dev/null || echo "0")

echo "Active targets: $active"
echo "Dropped targets: $dropped"

# List orchestrator-api targets
echo ""
echo "Orchestrator API targets:"
echo "$response" | jq '.data.activeTargets[] | select(.labels.job == "orchestrator-api") | {job: .labels.job, instance: .labels.instance, state: .health}' 2>/dev/null

echo ""
echo "=== Prometheus Test Complete ==="
