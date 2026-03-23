#!/bin/bash

# Test script for Orchestrator API
set -e

echo "=== Testing Orchestrator API ==="

# Port forward to API
echo "Setting up port-forward to Orchestrator API..."
kubectl port-forward -n orchestrator svc/orchestrator-api 8080:8080 &
PF_PID=$!
sleep 2

trap "kill $PF_PID 2>/dev/null || true" EXIT

API_URL="http://localhost:8080"

# Test health endpoint
echo ""
echo "=== Testing Health Endpoint ==="
response=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/healthz")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" = "200" ]; then
    echo "✅ /healthz endpoint is healthy (HTTP $http_code)"
else
    echo "❌ /healthz endpoint failed (HTTP $http_code)"
    echo "Response: $body"
fi

# Test readiness endpoint
echo ""
echo "=== Testing Readiness Endpoint ==="
response=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/readyz")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" = "200" ]; then
    echo "✅ /readyz endpoint is ready (HTTP $http_code)"
else
    echo "❌ /readyz endpoint failed (HTTP $http_code)"
    echo "Response: $body"
fi

# Test metrics endpoint
echo ""
echo "=== Testing Metrics Endpoint ==="
response=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/metrics")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" = "200" ]; then
    echo "✅ /metrics endpoint is available (HTTP $http_code)"
    # Show sample of metrics
    echo "Sample metrics:"
    echo "$body" | grep "^orchestrator_" | head -5
else
    echo "❌ /metrics endpoint failed (HTTP $http_code)"
fi

# Test POST /run endpoint (submit a job)
echo ""
echo "=== Testing POST /v1/run Endpoint ==="
payload=$(cat <<EOF
{
  "job_type": "INFERENCE",
  "application": "test_app",
  "tenant": "thinklabs",
  "workflow_id": "test_workflow_001",
  "input": {
    "uri": "s3://test-bucket/input.zarr",
    "format": "zarr"
  },
  "output": {
    "uri": "s3://test-bucket/output.zarr",
    "format": "zarr"
  }
}
EOF
)

response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/v1/run" \
  -H "Content-Type: application/json" \
  -d "$payload")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" = "200" ] || [ "$http_code" = "202" ]; then
    echo "✅ POST /v1/run succeeded (HTTP $http_code)"
    echo "Response:"
    echo "$body" | jq '.' 2>/dev/null || echo "$body"
    # Extract run_id for further testing
    run_id=$(echo "$body" | jq -r '.run_id' 2>/dev/null || echo "")
    
    if [ -n "$run_id" ] && [ "$run_id" != "null" ]; then
        echo ""
        echo "=== Testing GET /v1/runs/{run_id} Endpoint ==="
        echo "Retrieving run: $run_id"
        
        # Wait a moment for the run to be stored
        sleep 1
        
        run_response=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/v1/runs/$run_id")
        run_http_code=$(echo "$run_response" | tail -n1)
        run_body=$(echo "$run_response" | sed '$d')
        
        if [ "$run_http_code" = "200" ]; then
            echo "✅ GET /v1/runs/{run_id} succeeded (HTTP $run_http_code)"
            echo "Run Status:"
            echo "$run_body" | jq '.' 2>/dev/null || echo "$run_body"
        else
            echo "⚠️  GET /v1/runs/{run_id} returned HTTP $run_http_code"
            echo "Response: $run_body"
        fi
    fi
else
    echo "❌ POST /v1/run failed (HTTP $http_code)"
    echo "Response: $body"
fi

echo ""
echo "=== Orchestrator API Test Complete ==="
