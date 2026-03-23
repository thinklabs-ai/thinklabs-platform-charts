#!/bin/bash

# Test script for Grafana Dashboards
set -e

echo "=== Testing Grafana ==="

# Port forward to Grafana
echo ""
echo "Setting up port-forward to Grafana..."
kubectl port-forward -n monitoring monitoring-grafana-5c6cbddb9d-q2x8g 3000:3000 &
PF_PID=$!
sleep 4

trap "kill $PF_PID 2>/dev/null" EXIT

GRAFANA_URL="http://localhost:3000"

# Check Grafana health
echo ""
echo "=== Checking Grafana Health ==="
response=$(curl -s -w "\n%{http_code}" -X GET "$GRAFANA_URL/api/health")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" = "200" ]; then
    echo "✅ Grafana is healthy"
    status=$(echo "$body" | jq -r '.status' 2>/dev/null || echo "unknown")
    echo "Status: $status"
else
    echo "❌ Grafana health check failed (HTTP $http_code)"
fi

# Get default admin credentials info
echo ""
echo "=== Grafana Access Information ==="
echo "Grafana URL: http://localhost:3000"
echo "Default credentials (if not changed):"
echo "  Username: admin"
echo "  Password: prom-operator (default Helm chart password)"

# Check data sources with authentication
echo ""
echo "=== Checking Data Sources ==="
echo "Attempting to get data sources..."

# Try to get data sources with default credentials
response=$(curl -s -u admin:prom-operator -X GET "$GRAFANA_URL/api/datasources" 2>/dev/null)
ds_count=$(echo "$response" | jq '. | length' 2>/dev/null || echo "0")

if [ "$ds_count" -gt "0" ]; then
    echo "✅ Found $ds_count data source(s):"
    echo "$response" | jq -r '.[] | "  - \(.name) (\(.type))"' 2>/dev/null || echo "  (Data sources available)"
else
    echo "⚠️  Could not retrieve data sources (may require different credentials)"
fi

# List dashboards
echo ""
echo "=== Checking Dashboards ==="
response=$(curl -s -u admin:prom-operator -X GET "$GRAFANA_URL/api/search?query=" 2>/dev/null)
dashboard_count=$(echo "$response" | jq '. | length' 2>/dev/null || echo "0")

if [ "$dashboard_count" -gt "0" ]; then
    echo "✅ Found $dashboard_count dashboard(s):"
    echo "$response" | jq -r '.[] | "  - \(.title) [type: \(.type)]"' 2>/dev/null || echo "  (Dashboards available)"
else
    echo "⚠️  No dashboards found"
fi

# Get org info
echo ""
echo "=== Grafana Organization Info ==="
response=$(curl -s -u admin:prom-operator -X GET "$GRAFANA_URL/api/org" 2>/dev/null)
org_name=$(echo "$response" | jq -r '.name' 2>/dev/null || echo "unknown")
echo "Organization: $org_name"

# Summary
echo ""
echo "=== Grafana Test Summary ==="
echo "Grafana Dashboard URL: http://localhost:3000"
echo "Log in with credentials and verify:"
echo "  1. Prometheus data source is configured"
echo "  2. Orchestrator dashboards are available"
echo "  3. Metrics are being displayed correctly"

echo ""
echo "=== Grafana Test Complete ==="
echo "Note: Keep the port-forward running to access Grafana"
echo "Press Ctrl+C to stop the port-forward"

# Keep running
wait $PF_PID
