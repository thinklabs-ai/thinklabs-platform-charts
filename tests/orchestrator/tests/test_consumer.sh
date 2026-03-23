#!/bin/bash

# Test script for Status Consumer
set -e

echo "=== Testing Status Consumer ==="

# Check if consumer pod is running
echo ""
echo "=== Checking Consumer Pod Status ==="
pod_name=$(kubectl get pod -n orchestrator -l app=status-consumer -o jsonpath='{.items[0].metadata.name}')

if [ -z "$pod_name" ]; then
    echo "❌ No status-consumer pod found"
    exit 1
fi

echo "Pod name: $pod_name"

pod_status=$(kubectl get pod -n orchestrator "$pod_name" -o jsonpath='{.status.phase}')
if [ "$pod_status" = "Running" ]; then
    echo "✅ Status consumer pod is running"
else
    echo "❌ Status consumer pod is not running (status: $pod_status)"
    exit 1
fi

# Check pod logs for any errors
echo ""
echo "=== Checking Consumer Logs (last 20 lines) ==="
echo "----------"
kubectl logs -n orchestrator "$pod_name" --tail=20 2>/dev/null || echo "No logs available"
echo "----------"

# Check if consumer is subscribed to status topic
echo ""
echo "=== Checking Consumer Configuration ==="
echo "Environment variables in consumer pod:"
kubectl exec -n orchestrator "$pod_name" -- env | grep -E "KAFKA|TOPIC|REDIS|OTEL" || echo "Could not retrieve env vars"

# Test consumer connectivity to Kafka
echo ""
echo "=== Testing Consumer Connectivity ==="

# Submit a test job to generate a status message
echo "Submitting test job to generate status messages..."
kubectl port-forward -n orchestrator svc/orchestrator-api 8080:8080 &
PF_PID=$!
sleep 2

trap "kill $PF_PID 2>/dev/null || true" EXIT

payload=$(cat <<EOF
{
  "job_type": "INFERENCE",
  "application": "test_app",
  "tenant": "thinklabs",
  "workflow_id": "consumer_test_001",
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

response=$(curl -s -X POST "http://localhost:8080/v1/run" \
  -H "Content-Type: application/json" \
  -d "$payload")

run_id=$(echo "$response" | jq -r '.run_id' 2>/dev/null || echo "")

if [ -n "$run_id" ] && [ "$run_id" != "null" ]; then
    echo "✅ Test job submitted with run_id: $run_id"
    
    # Wait for consumer to process
    echo "Waiting for consumer to process status messages (5 seconds)..."
    sleep 5
    
    echo ""
    echo "Recent consumer logs after job submission:"
    kubectl logs -n orchestrator "$pod_name" --tail=10
else
    echo "⚠️  Could not submit test job"
fi

echo ""
echo "=== Status Consumer Test Complete ==="
