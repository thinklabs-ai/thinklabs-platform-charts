# Thinklabs MLOps Orchestrator - Test Suite

This directory contains comprehensive test scripts to validate the deployment of the orchestrator system and its components.

## Test Scripts

### Prerequisites

- `kubectl` configured to access the Kubernetes cluster
- `curl` for making HTTP requests
- `jq` for JSON parsing
- `nc` (netcat) for connectivity tests

Some tests require tools to be available in:
- `kafka-topics.sh` in PATH or Kafka installed

### Individual Tests

#### 1. **test_kafka.sh** - Kafka Connectivity & Topics Test
Tests Kafka broker connectivity and verifies that required topics are created.

**What it validates:**
- Kafka broker is reachable
- All required topics exist:
  - `thinklabs.mlops.request`
  - `thinklabs.mlops.status`
  - `thinklabs.mlops.response`
- Topic partitions and replication factors are correct

**Run:**
```bash
bash tests/test_kafka.sh
```

#### 2. **test_redis.sh** - Redis Connectivity Test
Tests Redis service connectivity and basic operations.

**What it validates:**
- Redis pod is running
- Redis service is accessible
- PING command works
- SET/GET operations work
- Redis server info (version, memory, etc.)
- Connected clients
- Persistence (RDB save status)

**Run:**
```bash
bash tests/test_redis.sh
```

**Expected Output:**
- Redis pod should be Running
- PING should return PONG
- SET/GET operations should succeed
- Should show Redis version, memory usage, and client count

#### 3. **test_api.sh** - Orchestrator API Test
Tests the orchestrator API endpoints and job submission functionality.

**What it validates:**
- API health check (`/healthz`)
- API readiness check (`/readyz`)
- Prometheus metrics endpoint (`/metrics`)
- Job submission (`POST /v1/run`)
- Job status retrieval (`GET /v1/runs/{run_id}`)

**Run:**
```bash
bash tests/test_api.sh
```

**Expected Output:**
- Health and readiness checks should return HTTP 200
- Metrics endpoint should return Prometheus-formatted metrics
- Job submission should return a run_id
- Job status retrieval should return job details

#### 4. **test_consumer.sh** - Status Consumer Test
Tests the status consumer pod and its ability to process Kafka messages.

**What it validates:**
- Status consumer pod is running
- Consumer is properly configured with environment variables
- Consumer can connect to Kafka and process messages
- Generates test messages and observes consumer processing

**Run:**
```bash
bash tests/test_consumer.sh
```

**Expected Output:**
- Consumer pod should be in Running state
- Recent logs should show message processing
- Test job submission should generate status messages

#### 5. **test_prometheus.sh** - Prometheus Monitoring Test
Tests Prometheus connectivity and metric scraping.

**What it validates:**
- Prometheus is healthy and responding
- Prometheus API is working
- Orchestrator API metrics are being scraped:
  - `orchestrator_http_requests_total`
  - `orchestrator_http_request_duration_seconds`
- Pod uptime metrics are available
- Active targets are configured

**Run:**
```bash
bash tests/test_prometheus.sh
```

**Access Prometheus UI:**
```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Visit http://localhost:9090
```

#### 6. **test_grafana.sh** - Grafana Dashboards Test
Tests Grafana connectivity and dashboard availability.

**What it validates:**
- Grafana is healthy and responding
- Data sources are configured
- Dashboards are available
- Organization is set up

**Run:**
```bash
bash tests/test_grafana.sh
```

**Access Grafana UI:**
```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# Visit http://localhost:3000
# Login: admin / prom-operator (default)
```

### Run All Tests

Run all test scripts in sequence with:

```bash
bash tests/run_all_tests.sh
```

This will run:
1. Kafka test
2. Redis test
3. API test
4. Consumer test
5. Prometheus test
6. Grafana test

And provide a summary of passed/failed tests.

## Troubleshooting

### Test Kafka Script
- **"Kafka broker is NOT reachable"**: Verify Kafka pod is running with `kubectl get pods -n kafka`
- **"Topic does NOT exist"**: Check kafka-create-topics job logs: `kubectl logs -n orchestrator <job_pod_name>`

### Test API Script
- **Port-forward fails**: Verify orchestrator-api service exists: `kubectl get svc -n orchestrator`
- **Connection refused**: Check if orchestrator-api pods are running: `kubectl get pods -n orchestrator`

### Test Consumer Script
- **No status-consumer pod**: Verify it's deployed: `kubectl get pods -n orchestrator -l app=status-consumer`
- **"Could not retrieve env vars"**: Consumer may not have exec permissions

### Test Prometheus Script
- **API returns error**: Check Prometheus logs: `kubectl logs -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0`
- **No metrics available**: May take 5-10 minutes for initial scraping

### Test Grafana Script
- **Cannot access dashboards**: Use Grafana UI credentials instead
- **Default credentials don't work**: Check ConfigMap: `kubectl get cm -n monitoring monitoring-grafana -o yaml`

## Access URLs (via port-forward)

When port-forwarding is active:

| Service | URL | Port Command |
|---------|-----|--------------|
| Orchestrator API | http://localhost:8080 | `kubectl port-forward -n orchestrator svc/orchestrator-api-thinklabs-orchestrator 8080:8080` |
| Prometheus | http://localhost:9090 | `kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090` |
| Grafana | http://localhost:3000 | `kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80` |
| Kafka Broker | localhost:29092 | `kubectl port-forward -n kafka svc/kafka-kafka 29092:9092` |

## Example Workflow

1. **Check deployment status:**
   ```bash
   kubectl get pods -n orchestrator
   kubectl get pods -n kafka
   kubectl get pods -n monitoring
   ```

2. **Run basic tests:**
   ```bash
   bash tests/test_kafka.sh
   bash tests/test_api.sh
   ```

3. **Test end-to-end flow:**
   ```bash
   bash tests/test_consumer.sh  # Submits a job and monitors consumer
   ```

4. **Check monitoring:**
   ```bash
   bash tests/test_prometheus.sh
   bash tests/test_grafana.sh
   ```

5. **Clean up:**
   - Stop all port-forward processes with `Ctrl+C`

## Performance Testing

For load testing the API, you can extend `test_api.sh` to:

```bash
# Submit multiple jobs
for i in {1..100}; do
    curl -X POST "http://localhost:8080/v1/run" \
      -H "Content-Type: application/json" \
      -d '{"job_type":"test","application":"load_test","tenant":"thinklabs"}'
done
```

Then monitor metrics in Prometheus/Grafana.

## Notes

- Tests use `port-forward` for connectivity, which is suitable for testing but not production access
- Some API tests generate real jobs - these will appear in Kafka and Redis
- Consumer test waits 5 seconds to allow time for processing
- Prometheus may take a few minutes to scrape initial metrics
