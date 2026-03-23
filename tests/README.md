# Testing Architecture - Platform Charts

## 📊 Overview

The testing structure is organized by modules, with each module having its own test suite that can be run independently or as part of the platform-wide testing.

## 🏗️ Directory Structure

```
tests/
├── all-tests.sh              # Master test runner (runs all modules)
├── shared/                   # Shared testing utilities
│   └── test-utils.sh         # Common functions, assertions, helpers
│
├── orchestrator/             # Orchestrator module tests
│   ├── test-runner.sh        # Module test orchestrator
│   ├── helm/                 # Helm chart verification tests
│   │   ├── verify-helm-install.sh
│   │   ├── component-health-check.sh
│   │   ├── integration-tests.sh
│   │   └── e2e-tests.sh
│   └── tests/                # Unit tests (existing)
│       ├── test_kafka.sh
│       ├── test_redis.sh
│       ├── test_api.sh
│       ├── test_consumer.sh
│       ├── test_prometheus.sh
│       ├── test_grafana.sh
│       └── run_all_tests.sh
│
├── document-generator/       # Document generator module tests
│   ├── test-runner.sh        # Module test orchestrator
│   └── helm/                 # Helm tests (template ready)
│
└── README.md                 # This file
```

## 🚀 Usage

### Run All Module Tests

```bash
cd tests

# Run all modules
./all-tests.sh

# Or explicitly
./all-tests.sh all
```

### Run Single Module Tests

```bash
# Test orchestrator module
./all-tests.sh orchestrator

# Test document-generator module
./all-tests.sh document-generator

# Run orchestrator's test-runner directly
./orchestrator/test-runner.sh
```

### Run Specific Test Type

```bash
# Run only Helm verification for orchestrator
./orchestrator/helm/verify-helm-install.sh

# Run only component health checks
./orchestrator/helm/component-health-check.sh

# Run only integration tests
./orchestrator/helm/integration-tests.sh

# Run only unit tests
./orchestrator/tests/run_all_tests.sh
```

### List Available Modules

```bash
./all-tests.sh list
```

### View Help

```bash
./all-tests.sh help
```

## 📋 Test Organization

### By Module

Each module has:

1. **Module Test Runner** (`test-runner.sh`)
   - Orchestrates all tests for that module
   - Can be called independently
   - Returns unified test summary

2. **Helm Tests** (`helm/`)
   - Chart validation and linting
   - Deployment verification
   - Component health checks
   - Integration tests
   - End-to-end testing

3. **Unit Tests** (`tests/` - orchestrator only)
   - Individual component tests (Kafka, Redis, API, etc.)
   - Existing test suite
   - Can be run separately

### Shared Utilities

The `shared/test-utils.sh` provides:

```bash
# Logging functions
log_header()        # Print section header
log_section()       # Print subsection
log_test()          # Log test execution
log_success()       # Log successful test
log_error()         # Log failed test
log_warning()       # Log warning
log_skip()          # Log skipped test
log_info()          # Log informational message
log_debug()         # Log debug info (if DEBUG=1)

# Assertion functions
assert_command_exists()      # Check if command is available
assert_file_exists()         # Check if file exists
assert_directory_exists()    # Check if directory exists
assert_equals()              # Compare values
assert_not_empty()           # Check value is not empty

# Kubernetes helpers
k8s_get_pod()                # Get pod name by label
k8s_get_service()            # Get service name by label
k8s_pod_ready()              # Check if pod is running
k8s_deployment_ready()       # Check if deployment is ready
k8s_get_env()                # Get environment variable from pod

# Network testing
test_tcp_connection()        # Test TCP connectivity
test_http_endpoint()         # Test HTTP endpoint

# Utility functions
print_test_summary()         # Print test results
cleanup_port_forward()       # Cleanup port-forward
get_script_dir()             # Resolve script directory
find_platform_charts_root()  # Find repo root
wait_for()                   # Wait with timeout
```

## 🔧 Adding Tests for a New Module

1. **Create module directory:**
```bash
mkdir -p tests/your-new-module/{helm,unit}
```

2. **Copy test runner template:**
```bash
cp tests/document-generator/test-runner.sh tests/your-new-module/
# Edit to use your module name and namespace
```

3. **Add Helm tests:**
```bash
# Create your Helm test scripts in your-new-module/helm/
cp tests/orchestrator/helm/verify-helm-install.sh tests/your-new-module/helm/
# Customize for your chart and service
```

4. **Add unit tests** (optional):
```bash
# Create individual test scripts in tests/your-new-module/tests/
```

5. **The module is now integrated:**
```bash
# Run all tests including your new module
./all-tests.sh

# Or run just your module
./all-tests.sh your-new-module
```

## 📊 Test Execution Flow

### Master Test Runner (`all-tests.sh`)
```
all-tests.sh
├─ orchestrator/test-runner.sh
│  ├─ helm/verify-helm-install.sh
│  ├─ helm/component-health-check.sh
│  ├─ helm/integration-tests.sh
│  └─ tests/run_all_tests.sh
│
└─ document-generator/test-runner.sh
   └─ helm/verify-helm-install.sh
```

### Module Test Runner (`orchestrator/test-runner.sh`)
```
orchestrator/test-runner.sh
├─ helm/verify-helm-install.sh
├─ helm/component-health-check.sh
├─ helm/integration-tests.sh
└─ tests/run_all_tests.sh
```

## 🎯 Best Practices

1. **Use shared utilities** - Source `test-utils.sh` in all scripts for consistency
2. **DRY principle** - Extract common logic to shared utilities
3. **Clear naming** - Give tests descriptive names
4. **Modular design** - Each test should be independent
5. **Good documentation** - Document what each test does
6. **Handle failures gracefully** - Use assertions and error handling
7. **Color-coded output** - Use provided logging functions for consistency

## 💡 Examples

### Using Shared Utilities in a Test Script

```bash
#!/bin/bash

set -e

# Get shared directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
SHARED_DIR="$TESTS_ROOT/shared"

# Source utilities
source "$SHARED_DIR/test-utils.sh"

log_header "My Test Suite"

# Check prerequisites
log_section "Checking Prerequisites"
assert_command_exists kubectl "Kubernetes CLI"
assert_command_exists helm "Helm package manager"

# Test Kubernetes
log_section "Testing Kubernetes"
if k8s_deployment_ready "default" "my-app"; then
    log_success "Deployment is ready"
else
    log_error "Deployment is not ready"
fi

# Print results
print_test_summary
```

### Adding Tests to Orchestrator Module

```bash
# Add a new test script to orchestrator/helm/
cat > tests/orchestrator/helm/my-custom-test.sh << 'EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
source "$TESTS_ROOT/shared/test-utils.sh"

log_header "My Custom Test"

# Your tests here
log_test "Testing something"
log_success "Test passed"

print_test_summary
EOF

# Make it executable
chmod +x tests/orchestrator/helm/my-custom-test.sh

# Add it to orchestrator/test-runner.sh
```

## 📈 Test Coverage

### Orchestrator Module

- ✅ Helm chart validation
- ✅ Pod resource configuration
- ✅ Security context setup
- ✅ RBAC configuration
- ✅ Kafka connectivity
- ✅ Redis connectivity
- ✅ API endpoints
- ✅ Individual component tests
- *Future: E2E workflow testing*

### Document Generator Module

- ✅ Helm chart structure (template)
- *Future: Component health checks*
- *Future: Integration tests*

## 🚦 Test Statuses

- **✓** - Test passed
- **✗** - Test failed
- **!** - Warning (test passed but with concerns)
- **→** - Test skipped

## 🔍 Debugging Tests

Enable debug output:

```bash
# Run with debug enabled
DEBUG=1 ./tests/orchestrator/test-runner.sh
```

Check individual test scripts:

```bash
# Run a specific test directly
./tests/orchestrator/helm/verify-helm-install.sh my-namespace

# Check logs
kubectl logs -n my-namespace <pod-name>
```

## 📚 Related Documentation

- [../HELM_INSTALLATION_GUIDE.md](../HELM_INSTALLATION_GUIDE.md) - Helm installation details
- [../VERIFICATION_SUITE_README.md](../VERIFICATION_SUITE_README.md) - Verification suite details
- [../charts/orchestrator-api/README.md](../charts/orchestrator-api/README.md) - Chart documentation

## 🎓 Test Hierarchy

```
Platform Charts Testing
│
├─ Master Tests (all-tests.sh)
│  │
│  ├─ Orchestrator Module Tests
│  │  ├─ Helm Tests
│  │  │  ├─ Chart Validation
│  │  │  ├─ Component Health
│  │  │  ├─ Integration Tests
│  │  │  └─ E2E Tests
│  │  └─ Unit Tests
│  │     ├─ Kafka
│  │     ├─ Redis
│  │     ├─ API
│  │     ├─ Consumer
│  │     ├─ Prometheus
│  │     └─ Grafana
│  │
│  └─ Document Generator Module Tests
│     └─ Helm Tests (template ready)
│
└─ Individual Module Tests (run independently)
```

---

**Last Updated:** March 23, 2026
**Testing Framework:** Bash with shared utilities
**Kubernetes Support:** 1.20+
**Helm Support:** 3.0+
