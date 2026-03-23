# Orchestrator Module Tests

## 📋 Overview

The orchestrator module contains comprehensive tests for the Helm chart and the orchestrator components (API, Status Consumer, etc.).

## 🏗️ Structure

```
orchestrator/
├── test-runner.sh              # Run all orchestrator tests
├── helm/                       # Helm chart validation tests
│   ├── verify-helm-install.sh
│   ├── component-health-check.sh
│   ├── integration-tests.sh
│   └── e2e-tests.sh
└── tests/                      # Unit tests
    ├── test_kafka.sh
    ├── test_redis.sh
    ├── test_api.sh
    ├── test_consumer.sh
    ├── test_prometheus.sh
    ├── test_grafana.sh
    └── run_all_tests.sh
```

## 🚀 Quick Start

### Run All Orchestrator Tests

```bash
# From tests directory
./orchestrator/test-runner.sh

# With custom namespace
./orchestrator/test-runner.sh my-orchestrator-ns
```

### Run Helm Tests Only

```bash
# All Helm tests
./orchestrator/helm/verify-helm-install.sh

# Specific Helm test
./orchestrator/helm/component-health-check.sh my-namespace
./orchestrator/helm/integration-tests.sh my-namespace
./orchestrator/helm/e2e-tests.sh my-namespace orchestrator true false
```

### Run Unit Tests Only

```bash
./orchestrator/tests/run_all_tests.sh
```

## 📊 Test Suite Overview

### Helm Tests

#### 1. **verify-helm-install.sh** - Main Verification
Tests the overall Helm installation and Kubernetes resources.

**Tests:**
- Prerequisites check (kubectl, helm, kubeconfig)
- Helm chart validation and linting
- Template rendering
- Release status verification
- Deployment readiness
- Service availability
- API endpoints (health, readiness, inference)
- Configuration validation
- Pod logs analysis

**Usage:**
```bash
./orchestrator/helm/verify-helm-install.sh [NAMESPACE] [RELEASE] [KUBECONFIG]
```

#### 2. **component-health-check.sh** - Component Validation
Deep validation of component configurations and best practices.

**Tests:**
- Pod resource requests/limits
- Health probes (liveness, readiness, startup)
- Security context
- RBAC configuration
- Network policies
- ConfigMaps and Secrets
- Container images and tags
- Pod affinity/topology

**Usage:**
```bash
./orchestrator/helm/component-health-check.sh [NAMESPACE]
```

#### 3. **integration-tests.sh** - Integration Testing
Tests actual connectivity and API functionality.

**Tests:**
- Kafka broker connectivity
- Kafka topics verification
- Redis connectivity and PING
- OpenTelemetry collector connectivity
- API endpoints (health, readiness, inference)
- Run status endpoints
- Deployment events

**Usage:**
```bash
./orchestrator/helm/integration-tests.sh [NAMESPACE] [TIMEOUT]
```

#### 4. **e2e-tests.sh** - End-to-End Testing
Complete workflow testing with 6 stages:

1. Pre-flight checks
2. Helm installation (dry-run or real)
3. Deployment verification
4. Component health checks
5. Integration tests
6. Cleanup and summary

**Usage:**
```bash
./orchestrator/helm/e2e-tests.sh [NAMESPACE] [RELEASE] [DRY_RUN] [CLEANUP]

# Examples:
./orchestrator/helm/e2e-tests.sh orchestrator orchestrator true false
./orchestrator/helm/e2e-tests.sh orchestrator orchestrator false false
```

### Unit Tests

The `tests/` directory contains individual component tests:

- **test_kafka.sh** - Kafka connectivity and topic verification
- **test_redis.sh** - Redis connectivity and operations
- **test_api.sh** - API endpoint testing
- **test_consumer.sh** - Status consumer testing
- **test_prometheus.sh** - Prometheus metrics verification
- **test_grafana.sh** - Grafana dashboard verification

## 🔧 Configuration

### Default Namespace
Tests default to `orchestrator` namespace. Override with:

```bash
./orchestrator/test-runner.sh my-custom-namespace
```

### Environment Variables

```bash
# Enable debug output
DEBUG=1 ./orchestrator/test-runner.sh

# Custom kubeconfig
KUBECONFIG=/path/to/config ./orchestrator/helm/verify-helm-install.sh
```

## 📈 Test Coverage

- ✅ Helm chart syntax and validation
- ✅ Chart template rendering
- ✅ Kubernetes resource creation
- ✅ Pod configuration and security
- ✅ Deployment readiness
- ✅ External dependency connectivity
- ✅ API endpoint functionality
- ✅ Component health metrics
- ✅ Configuration validation

## 🎯 Recommended Test Order

1. **verify-helm-install.sh** - Quick overall check (3-5 min)
2. **component-health-check.sh** - Component validation (2-3 min)
3. **integration-tests.sh** - Connectivity testing (5-10 min)
4. **Unit tests** - Individual component tests (varies)

**Total time:** ~15-30 minutes

## 🚦 Example Output

### Successful Test Run

```
════════════════════════════════════════════════════════════
     Orchestrator Module Test Suite
════════════════════════════════════════════════════════════

Module: orchestrator
Namespace: orchestrator

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Running Helm Verification Tests
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[TEST] Running: verify-helm-install.sh
[✓] kubectl is installed
[✓] helm is installed
[✓] Helm chart linting passed
... (more tests)

════════════════════════════════════════════════════════════
TEST SUMMARY
════════════════════════════════════════════════════════════

Passed:  25
Failed:  0
Warned:  0
Skipped: 0
Total:   25

✓ All tests passed!
```

### Failed Test Run

```
[✗] Deployment 'orchestrator-api' not ready (0/1)
[✗] Health endpoint is not responding (HTTP 503)

════════════════════════════════════════════════════════════
✗ Some tests failed. Please review the output above.
════════════════════════════════════════════════════════════
```

## 🔍 Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n orchestrator

# Check pod events
kubectl describe pod -n orchestrator <pod-name>

# Check logs
kubectl logs -n orchestrator <pod-name>
```

### Kafka Connection Issues

```bash
# Verify Kafka broker address
kubectl get deployment -n orchestrator -o yaml | grep KAFKA_BROKERS

# Test from a pod
kubectl exec -n orchestrator <pod-name> -- \
  bash -c 'echo "Testing Kafka at $KAFKA_BROKERS"'
```

### API Not Responding

```bash
# Port-forward to API service
kubectl port-forward -n orchestrator svc/orchestrator-api 8080:8080

# Test endpoints
curl http://localhost:8080/healthz
curl http://localhost:8080/readyz
```

## 📚 Related Documentation

- [../HELM_INSTALLATION_GUIDE.md](../HELM_INSTALLATION_GUIDE.md) - Helm installation
- [../charts/orchestrator-api/README.md](../charts/orchestrator-api/README.md) - Chart details
- [../tests/README.md](../README.md) - Testing overview

## 💡 Tips

1. Always start with `verify-helm-install.sh` for a quick check
2. Use dry-run mode first: `e2e-tests.sh ... true false`
3. Capture output for troubleshooting: `test-runner.sh 2>&1 | tee results.log`
4. Enable debug mode for verbose output: `DEBUG=1 test-runner.sh`
5. Run individual tests if needed to isolate issues

---

**Last Updated:** March 23, 2026
**Module:** orchestrator
**Test Count:** 100+ individual tests
**Estimated Runtime:** 15-30 minutes (full suite)
