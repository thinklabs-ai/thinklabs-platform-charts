# Testing Guide - Platform Charts

## 🎯 Overview

This comprehensive guide covers the modular testing architecture for ThinkLabs Platform Charts, supporting Helm verification, component health checks, integration tests, and unit testing.

---

## 📊 What Was Created

A scalable testing infrastructure with **7 new executable scripts**:

### **Master Test Infrastructure**
- `tests/all-tests.sh` - Master runner that discovers and executes all module tests
- `tests/shared/test-utils.sh` - Shared utilities library with 60+ reusable functions

### **Orchestrator Module Tests** (moved from root to organized structure)
- `tests/orchestrator/test-runner.sh` - Module-specific test orchestrator
- `tests/orchestrator/helm/verify-helm-install.sh` - Main Helm verification
- `tests/orchestrator/helm/component-health-check.sh` - Component validation
- `tests/orchestrator/helm/integration-tests.sh` - Connectivity testing
- `tests/orchestrator/helm/e2e-tests.sh` - End-to-end testing

### **Template for New Modules**
- `tests/document-generator/test-runner.sh` - Ready to customize for new services

### **Documentation**
- `tests/README.md` - Complete architecture guide
- `tests/orchestrator/README.md` - Module documentation
- `TESTING.md` - This file

---

## 📁 Directory Structure

```
thinklabs-platform-charts/
│
├── charts/
│   ├── orchestrator-api/
│   └── document-generator-service/
│
├── tests/                              # Master tests directory
│   ├── all-tests.sh                   # Master test runner (NEW)
│   ├── README.md                      # Architecture docs
│   │
│   ├── shared/                        # Shared utilities (NEW)
│   │   └── test-utils.sh              # 60+ reusable functions
│   │
│   ├── orchestrator/                  # Orchestrator module tests
│   │   ├── README.md                  # Module documentation
│   │   ├── test-runner.sh             # Module orchestrator (NEW)
│   │   ├── helm/                      # Helm verification tests (MOVED)
│   │   │   ├── verify-helm-install.sh
│   │   │   ├── component-health-check.sh
│   │   │   ├── integration-tests.sh
│   │   │   └── e2e-tests.sh
│   │   └── tests/                     # Unit tests (EXISTING)
│   │       ├── test_kafka.sh
│   │       ├── test_redis.sh
│   │       ├── test_api.sh
│   │       ├── test_consumer.sh
│   │       ├── test_prometheus.sh
│   │       ├── test_grafana.sh
│   │       ├── run_all_tests.sh
│   │       └── README.md
│   │
│   └── document-generator/            # Document generator module (TEMPLATE)
│       ├── test-runner.sh
│       └── helm/
│
├── TESTING.md                         # This guide
├── HELM_VERIFICATION.md               # Installation & verification guide
└── README.md                          # Project README
```

---

## 🚀 Usage Patterns

### **Pattern 1: Run All Platform Tests** (Helm + Unit)
```bash
cd tests
./all-tests.sh
```
Output: Runs orchestrator module (helm + unit) then document-generator, unified summary

---

### **Pattern 2: Test Single Module**
```bash
# Discover available modules
./all-tests.sh list

# Run specific module
./all-tests.sh orchestrator
# OR
./orchestrator/test-runner.sh
```

---

### **Pattern 3: Run Specific Test Layer** (Helm only or Unit only)
```bash
# Helm verification tests only
./orchestrator/helm/verify-helm-install.sh

# Unit tests only
./orchestrator/tests/run_all_tests.sh

# Component health checks
./orchestrator/helm/component-health-check.sh

# Integration tests
./orchestrator/helm/integration-tests.sh
```

---

### **Pattern 4: Custom Namespace**
```bash
# Test in custom namespace
./orchestrator/test-runner.sh my-namespace

# Or pass to specific test
./orchestrator/helm/verify-helm-install.sh my-namespace
```

---

## 🔄 Testing Layers

The new architecture supports **two testing layers** that complement each other:

### **Layer 1: Helm Verification Tests** (Component deployment validation)
Located in `tests/orchestrator/helm/`:
- Chart syntax and template validation
- Kubernetes resource configuration
- Pod readiness and health probes
- Service availability
- API endpoints
- External connectivity (Kafka, Redis, OpenTelemetry)

**When to use:**
- Validating chart changes
- Post-deployment verification
- Production readiness checks
- Troubleshooting deployment issues

**Key scripts:**
- `verify-helm-install.sh` - Quick validation
- `component-health-check.sh` - Deep configuration review
- `integration-tests.sh` - API and dependency connectivity
- `e2e-tests.sh` - Full workflow testing with optional cleanup

---

### **Layer 2: Unit Tests** (Component functionality testing)
Located in `tests/orchestrator/tests/`:
- Kafka connectivity and topics
- Redis operations
- API endpoint responses
- Consumer message processing
- Prometheus metrics
- Grafana dashboard availability

**When to use:**
- Testing component code changes
- Integration validation
- Dependency availability
- Metric collection

**Available tests:**
- `test_kafka.sh` - Kafka broker and topics
- `test_redis.sh` - Redis service and operations
- `test_api.sh` - API endpoints
- `test_consumer.sh` - Status consumer
- `test_prometheus.sh` - Metrics server
- `test_grafana.sh` - Dashboard availability

---

## 🔑 Key Design Decisions

### 1. **Modular Organization**
Each module has its own directory structure with independent runners, enabling:
- Clear ownership and maintenance
- Easy addition of new modules
- Isolated test execution
- Per-module documentation

### 2. **Shared Utilities (DRY Principle)**
Common testing functions centralized in `tests/shared/test-utils.sh`:

**Logging Functions**
```bash
log_header "Main test title"
log_section "Sub-section"
log_test "Testing something"
log_success "Test passed"
log_error "Test failed"
log_warning "Warning detected"
log_skip "Test skipped"
```

**Kubernetes Helpers**
```bash
k8s_pod_ready "namespace" "pod-name"
k8s_deployment_ready "namespace" "deployment-name"
k8s_get_pod "namespace" "label=selector"
k8s_get_service "namespace" "label=selector"
k8s_get_env "namespace" "pod-name" "ENV_VAR"
```

**Network Testing**
```bash
test_tcp_connection "host" "port" "timeout"
test_http_endpoint "url" "method" "timeout"
```

**Assertions**
```bash
assert_command_exists "kubectl" "Kubernetes CLI"
assert_file_exists "/path/to/file"
assert_equals "value1" "value2" "test description"
assert_not_empty "variable" "variable description"
```

**Utilities**
```bash
wait_for "condition" "timeout" "check_interval"
find_platform_charts_root
cleanup_port_forward "pid"
print_test_summary
```

### 3. **Hierarchical Execution**
```
all-tests.sh (Master)
├─ orchestrator/test-runner.sh
│  ├─ helm/* (4 scripts - verification, health, integration, e2e)
│  └─ tests/* (7 scripts - kafka, redis, api, consumer, etc.)
└─ document-generator/test-runner.sh
```

### 4. **Auto-Discovery System**
New modules automatically included in `all-tests.sh` without code changes:
```bash
# Check available modules
./all-tests.sh list

# Automatically discovers any new module-runner.sh pattern
# in tests/**/test-runner.sh
```

---

## 🔧 Extending for New Modules

To add tests for a new service (e.g., `report-generator`):

### **Step 1: Create Module Structure**
```bash
mkdir -p tests/report-generator/{helm,tests}
```

### **Step 2: Create Module Test Runner**
```bash
cp tests/document-generator/test-runner.sh tests/report-generator/
```

### **Step 3: Customize test-runner.sh**
Edit `tests/report-generator/test-runner.sh`:
```bash
MODULE_NAME="report-generator"          # Change this
HELM_NAMESPACE="thinklabs-report-gen"  # Change this
HELM_RELEASE="report-gen"              # Change this
```

### **Step 4: Add Helm Tests (Optional)**
```bash
cp tests/orchestrator/helm/*.sh tests/report-generator/helm/
# Edit each script to use report-generator namespace/release
```

### **Step 5: Add Unit Tests**
Create test files in `tests/report-generator/tests/`:
```bash
cat > tests/report-generator/tests/test_api.sh << 'EOF'
#!/bin/bash
source "$(dirname "$0")/../../shared/test-utils.sh"

log_header "Report Generator API Tests"
# Add your tests here
EOF

chmod +x tests/report-generator/tests/test_api.sh
```

### **Step 6: Done!**
New module is automatically discovered:
```bash
./all-tests.sh list          # Shows report-generator
./all-tests.sh report-generator  # Runs its tests
./all-tests.sh               # Includes it in all-tests
```

---

## 📋 Test Descriptions

### **verify-helm-install.sh**
Main Helm chart verification covering:
- Chart syntax validation and linting
- Template rendering
- Release status
- Deployment readiness
- Service availability
- Pod configuration
- API endpoint health

```bash
./orchestrator/helm/verify-helm-install.sh [NAMESPACE] [RELEASE] [KUBECONFIG]
```

---

### **component-health-check.sh**
Deep validation of Kubernetes resource configuration:
- Pod resource requests/limits
- Liveness/readiness/startup probes
- Security context and RBAC
- Network policies and volume configuration
- Container image tags
- Pod affinity rules

```bash
./orchestrator/helm/component-health-check.sh [NAMESPACE]
```

---

### **integration-tests.sh**
Tests actual connectivity between components:
- Kafka broker and topics
- Redis connectivity
- OpenTelemetry collector
- API endpoints
- Pod event analysis

```bash
./orchestrator/helm/integration-tests.sh [NAMESPACE] [TIMEOUT]
```

---

### **e2e-tests.sh**
Six-stage end-to-end testing workflow:
1. Pre-flight checks (prerequisites)
2. Helm installation (or dry-run)
3. Deployment verification
4. Component tests
5. Integration tests
6. Cleanup and summary

```bash
./orchestrator/helm/e2e-tests.sh [NAMESPACE] [RELEASE] [DRY_RUN] [CLEANUP]
```

---

## 🎓 Test Patterns

### **Using Shared Utilities**
All test scripts should source the shared utilities:

```bash
#!/bin/bash
set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../shared/test-utils.sh"  # Adjust path as needed

log_header "My Test Suite"
log_section "Checking prerequisites"

# Use consistent logging
if command -v kubectl &> /dev/null; then
    log_success "kubectl is installed"
else
    log_error "kubectl is not installed"
fi

# Use assertions
assert_command_exists "kubectl" "Kubernetes CLI"
assert_command_exists "helm" "Helm package manager"

# Summary
print_test_summary
```

---

### **Writing Assertions**
```bash
# Command existence
assert_command_exists "jq" "JSON processor"

# File existence
assert_file_exists "$KUBECONFIG" "kubeconfig file"

# Value equality
assert_equals "actual_value" "expected_value" "Description"

# Non-empty values
assert_not_empty "VARIABLE" "Variable name"
```

---

### **Kubernetes Operations**
```bash
# Check if deployment is ready
if k8s_deployment_ready "orchestrator" "orchestrator-api"; then
    log_success "Deployment is ready"
else
    log_error "Deployment is not ready"
fi

# Get pod name by label
POD=$(k8s_get_pod "default" "app=myapp")

# Get environment variable from pod
REDIS_ADDR=$(k8s_get_env "default" "$POD" "REDIS_ADDR")

# Test network connectivity
test_tcp_connection "kafka-broker.kafka" "9092" "30s"
test_http_endpoint "http://localhost:8080/healthz" "GET" "10s"
```

---

## 📈 Quick Reference

| Task | Command |
|------|---------|
| List available modules | `./all-tests.sh list` |
| Run all tests | `./all-tests.sh` |
| Run orchestrator tests | `./all-tests.sh orchestrator` |
| Quick Helm check | `./orchestrator/helm/verify-helm-install.sh` |
| Component health | `./orchestrator/helm/component-health-check.sh` |
| Integration tests | `./orchestrator/helm/integration-tests.sh` |
| Full E2E test (dry-run) | `./orchestrator/helm/e2e-tests.sh myns orchestrator true false` |
| Unit tests only | `./orchestrator/tests/run_all_tests.sh` |
| Custom namespace | `./orchestrator/test-runner.sh my-namespace` |

---

## 🔗 Related Docs

- **[HELM_VERIFICATION.md](HELM_VERIFICATION.md)** - Detailed Helm installation and verification guide
- **[tests/README.md](tests/README.md)** - Testing architecture deep-dive
- **[tests/orchestrator/README.md](tests/orchestrator/README.md)** - Orchestrator module details
- **[README.md](README.md)** - Project overview
