# Helm Verification and Installation Guide

## 📋 Overview

This guide covers Helm installation of the ThinkLabs Orchestrator API on Kubernetes and comprehensive verification procedures to ensure all components are working correctly.

---

## 🚀 Quick Start

### Prerequisites Check
```bash
# Verify all required tools are installed
kubectl version --client
helm version
curl --version
kubectl cluster-info
```

### Quick Verification (5-10 minutes)
```bash
cd thinklabs-platform-charts
chmod +x tests/orchestrator/helm/*.sh
./tests/orchestrator/helm/verify-helm-install.sh
```

### Full Test Workflow
```bash
# Dry-run first to validate
./tests/orchestrator/helm/e2e-tests.sh orchestrator orchestrator true false

# Then run verification
./tests/orchestrator/helm/verify-helm-install.sh

# Component health check
./tests/orchestrator/helm/component-health-check.sh

# Integration tests
./tests/orchestrator/helm/integration-tests.sh
```

---

## 📋 Prerequisites

Ensure you have the following installed:
- **kubectl** (1.20+) - [Install](https://kubernetes.io/docs/tasks/tools/)
- **helm** (3.0+) - [Install](https://helm.sh/docs/intro/install/)
- **curl** (for API testing)
- **jq** (optional, for JSON parsing)
- Access to a Kubernetes cluster (EKS, AKS, GKE, or local)

### Verify Cluster Connection
```bash
# Check cluster info
kubectl cluster-info
kubectl get nodes

# List available contexts
kubectl config get-contexts

# Switch context if needed
kubectl config use-context <context-name>

# Verify permissions
kubectl auth can-i create deployments --all-namespaces
```

---

## 🔧 Installation Steps

### Option A: Installation with Default Values (Recommended)

#### Step 1: Dry-Run First (RECOMMENDED)
```bash
# Validate the chart without installing
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  --create-namespace \
  --dry-run \
  --debug
```

This will output all generated Kubernetes manifests. Review for any issues before proceeding.

#### Step 2: Perform Actual Installation
```bash
# Install with default values
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  --create-namespace

# Verify installation
helm status orchestrator -n orchestrator
kubectl get all -n orchestrator
```

---

### Option B: Installation with Custom Values

#### Step 1: Create Custom Values File
```bash
cat > custom-values.yaml << 'EOF'
# Namespace and environment
namespace: orchestrator
tenant: my-tenant
environment: dev

# Image repositories (if using private registry)
image:
  repository: your-registry/orchestrator-api
  tag: v0.1.0
  pullPolicy: IfNotPresent

statusConsumerImage:
  repository: your-registry/status-consumer
  tag: v0.1.0
  pullPolicy: IfNotPresent

# Kafka configuration
kafka:
  bootstrap: kafka-broker.kafka:9092
  securityProtocol: PLAINTEXT

# Redis configuration
redis:
  host: redis-service.redis:6379

# Environment variables
env:
  LOG_LEVEL: INFO
  OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector.observability:4318

# Pod resources
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"

# Replicas
replicaCount: 2
EOF
```

#### Step 2: Install with Custom Values
```bash
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  --create-namespace \
  -f custom-values.yaml

# Or use value overrides directly
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  --create-namespace \
  --set tenant=my-tenant \
  --set environment=prod \
  --set kafka.bootstrap=my-kafka:9092 \
  --set replicaCount=3
```

#### Step 3: Verify Installation
```bash
# Check release status
helm status orchestrator -n orchestrator

# List all resources
kubectl get all -n orchestrator

# Check pods in detail
kubectl get pods -n orchestrator -o wide
kubectl describe pods -n orchestrator

# View applied values
helm get values orchestrator -n orchestrator

# View all manifests
helm get manifest orchestrator -n orchestrator
```

---

## ✅ Verification Suite

Four comprehensive verification scripts are provided in `tests/orchestrator/helm/`:

### 1. **verify-helm-install.sh** - Main Verification

Comprehensive Helm chart and deployment verification.

```bash
./tests/orchestrator/helm/verify-helm-install.sh [NAMESPACE] [RELEASE] [KUBECONFIG]

# Examples:
./tests/orchestrator/helm/verify-helm-install.sh                    # defaults
./tests/orchestrator/helm/verify-helm-install.sh orchestrator orchestrator
```

**Tests Performed:**
- ✅ Prerequisites validation (kubectl, helm, kubeconfig)
- ✅ Helm chart linting and syntax
- ✅ Template rendering and manifest generation
- ✅ Release status verification
- ✅ Deployment readiness (replicas, availability, ready conditions)
- ✅ Service status and endpoints availability
- ✅ Pod resource limits and requests
- ✅ Environment variable configuration
- ✅ Pod logs analysis for errors
- ✅ Pod restart count analysis

**Output:** Detailed report with test count and summary

---

### 2. **component-health-check.sh** - Component Configuration Validation

Deep dive into Kubernetes resource configuration and best practices.

```bash
./tests/orchestrator/helm/component-health-check.sh [NAMESPACE]

# Example:
./tests/orchestrator/helm/component-health-check.sh orchestrator
```

**Tests Performed:**
- ✅ Pod resource requests/limits validation
- ✅ Liveness probe configuration review
- ✅ Readiness probe configuration review
- ✅ Startup probe configuration review
- ✅ Security context validation
- ✅ RBAC configuration and permissions
- ✅ Network policies and SecurityContext
- ✅ ConfigMaps and Secrets audit
- ✅ Volume configuration and mounts
- ✅ Container image tags (avoiding 'latest')
- ✅ Pod affinity, anti-affinity, and topology rules
- ✅ CPU/memory limits recommendations

**Output:** Health check report with recommendations

---

### 3. **integration-tests.sh** - Connectivity and API Testing

Tests actual component connectivity and API functionality.

```bash
./tests/orchestrator/helm/integration-tests.sh [NAMESPACE] [TIMEOUT]

# Examples:
./tests/orchestrator/helm/integration-tests.sh                     # defaults
./tests/orchestrator/helm/integration-tests.sh orchestrator 60
```

**Tests Performed:**
- ✅ Kafka broker connectivity and reachability
- ✅ Kafka topics existence and configuration
- ✅ Redis connectivity and PING command
- ✅ OpenTelemetry collector connectivity
- ✅ API health endpoint (`/healthz`)
- ✅ API readiness endpoint (`/readyz`)
- ✅ API inference endpoint (`POST /v1/inference`)
- ✅ API run status endpoint (`GET /v1/runs/{run_id}`)
- ✅ Deployment events for errors/warnings
- ✅ Response time measurements

**Output:** Integration test results with connectivity status

---

### 4. **e2e-tests.sh** - End-to-End Testing

Complete workflow testing with optional dry-run capability.

```bash
./tests/orchestrator/helm/e2e-tests.sh [NAMESPACE] [RELEASE] [DRY_RUN] [CLEANUP]

# Examples:
./tests/orchestrator/helm/e2e-tests.sh orchestrator orchestrator true false   # Dry-run, no cleanup
./tests/orchestrator/helm/e2e-tests.sh orchestrator orchestrator false false  # Full test, no cleanup
./tests/orchestrator/helm/e2e-tests.sh orchestrator orchestrator false true   # Full test + cleanup
```

**Test Stages:**
1. **Pre-flight Checks** - Prerequisites and cluster validation
2. **Helm Installation** - Install or dry-run the chart
3. **Deployment Verification** - Wait for pod readiness
4. **Component Tests** - Run component health checks
5. **Integration Tests** - Test connectivity and APIs
6. **Cleanup** - Optional cleanup and summary report

**Output:** Staged test results with recommendations at each stage

---

## 📊 Test Workflow Recommendations

### Scenario 1: Pre-Installation Validation (< 10 min)

Perfect for architecture planning or chart updates.

```bash
# Just validate the chart without installing
./tests/orchestrator/helm/e2e-tests.sh my-namespace orchestrator true false

# Then review the output to validate everything looks good
```

---

### Scenario 2: Quick Verification After Install (5-10 min)

Quick health check after deployment.

```bash
./tests/orchestrator/helm/verify-helm-install.sh my-namespace orchestrator
```

---

### Scenario 3: Comprehensive Health Check (15-20 min)

Full diagnostic for troubleshooting.

```bash
cd thinklabs-platform-charts

echo "=== Main Verification ==="
./tests/orchestrator/helm/verify-helm-install.sh

echo "=== Component Health ==="
./tests/orchestrator/helm/component-health-check.sh

echo "=== Integration Tests ==="
./tests/orchestrator/helm/integration-tests.sh

echo "=== All tests complete ==="
```

---

### Scenario 4: Production Deployment (20-30 min)

Full validation workflow before production.

```bash
# 1. Dry-run first
./tests/orchestrator/helm/e2e-tests.sh my-prod orchestrator true false

# 2. Review output and validate configuration

# 3. Perform actual installation
helm install orchestrator charts/orchestrator-api \
  --namespace my-prod \
  --create-namespace \
  -f prod-values.yaml

# 4. Run full verification suite
./tests/orchestrator/helm/verify-helm-install.sh my-prod orchestrator
./tests/orchestrator/helm/component-health-check.sh my-prod
./tests/orchestrator/helm/integration-tests.sh my-prod 60
```

---

## 🔍 Interpreting Test Results

### ✅ PASS - All Green

```
[✓] Health endpoint is responding
[✓] Readiness endpoint is responding
[✓] Pod 'orchestrator-api-xxx' is running

✅ All tests passed! Installation is working correctly.
```

**Action:** Your installation is working. Proceed with usage.

---

### ⚠️ WARNING - Yellow Flags

```
[!] Pod may be running as root (no runAsUser defined)
[!] Namespace does not exist - it will be created
[!] Found warnings in pod logs

⚠️ Some warnings detected. Review and fix if needed.
```

**Action:** Review warnings. Fix if they impact your requirements.

---

### ❌ FAIL - Red Stops

```
[✗] Helm chart linting failed: syntax error in values.yaml
[✗] Health endpoint not responding (HTTP 503)
[✗] Kafka broker not reachable

❌ Tests failed. See troubleshooting section.
```

**Action:** Stop. Debug and resolve the issue before proceeding.

---

## 🛠️ Troubleshooting Guide

### Problem: "Helm chart linting failed"

```bash
# Check what the error is
helm lint charts/orchestrator-api

# Inspect the chart structure
ls -la charts/orchestrator-api/
cat charts/orchestrator-api/Chart.yaml
cat charts/orchestrator-api/values.yaml

# Validate YAML syntax
yamllint charts/orchestrator-api/values.yaml
```

**Common Causes:**
- Invalid YAML syntax (indentation, quotes)
- Missing required fields in `Chart.yaml`
- Invalid Helm template syntax (incorrect `{{ }}`)
- Dependency not found

**Recovery:** Fix syntax errors and re-run linting.

---

### Problem: "Deployment not ready (0/1 replicas)"

```bash
# Check pod status
kubectl get pods -n orchestrator -o wide

# Describe pod for event details
kubectl describe pod -n orchestrator <pod-name>

# Check logs
kubectl logs -n orchestrator <pod-name>
kubectl logs -n orchestrator <pod-name> --previous  # If crashed

# Check recent events
kubectl get events -n orchestrator --sort-by='.lastTimestamp'
```

**Common Causes:**
- `ImagePullBackOff` - Wrong image repo/tag or missing credentials
- `CrashLoopBackOff` - Application startup failure, see logs
- `Pending` - Insufficient resources (CPU, memory)
- `CreateContainerConfigError` - Wrong ConfigMap/Secret reference

**Recovery:**
```bash
# For image pull errors, create image pull secret
kubectl create secret docker-registry regcred \
  --docker-server=your-registry \
  --docker-username=username \
  --docker-password=password \
  -n orchestrator

# Then update deployment to use the secret
helm upgrade orchestrator charts/orchestrator-api \
  --set image.imagePullSecrets[0].name=regcred
```

---

### Problem: "Kafka broker is not reachable"

```bash
# Verify Kafka broker address in deployment
kubectl get deployment -n orchestrator -o yaml | grep -A5 KAFKA_BOOTSTRAP

# Check Kafka service details
kubectl get svc -n kafka

# Test connectivity from pod
kubectl exec -n orchestrator <api-pod> -- \
  bash -c 'echo "Testing Kafka at $KAFKA_BOOTSTRAP"; nc -zv kafka-broker.kafka 9092'

# Or test from debug pod
kubectl run -n orchestrator --rm -it debug --image=busybox:1.28 \
  -- sh -c 'nslookup kafka-broker.kafka && nc -zv kafka-broker.kafka 9092'
```

**Common Causes:**
- Kafka service not running in cluster
- Wrong Kafka broker address in environment variables
- Network policy blocking traffic
- Kafka cluster in different namespace not accessible

**Recovery:**
```bash
# Verify Kafka is running
kubectl get pods -n kafka

# Update bootstrap address if wrong
helm upgrade orchestrator charts/orchestrator-api \
  --set kafka.bootstrap=kafka-broker.kafka:9092 \
  -n orchestrator
```

---

### Problem: "Redis connection failed"

```bash
# Verify Redis address
kubectl get deployment -n orchestrator -o yaml | grep REDIS

# Test Redis connectivity
kubectl run -n orchestrator --rm -it debug --image=redis:alpine \
  -- redis-cli -h redis-service.redis -p 6379 ping

# Check Redis service
kubectl get svc -n redis
kubectl describe svc redis-service -n redis
```

**Common Causes:**
- Redis service not running
- Wrong host/port in environment variables
- Network policy blocking access
- Redis authentication required but not configured

**Recovery:**
```bash
# Update Redis address
helm upgrade orchestrator charts/orchestrator-api \
  --set env.REDIS_ADDR=redis-service.redis:6379 \
  -n orchestrator

# Check Redis is running
kubectl get pods -n redis
```

---

### Problem: "API not responding to health check"

```bash
# Port-forward to test locally
kubectl port-forward -n orchestrator svc/orchestrator-api 8080:8080

# In another terminal, test endpoints
curl -v http://localhost:8080/healthz
curl -v http://localhost:8080/readyz

# Check pod logs for startup errors
kubectl logs -n orchestrator <pod-name> | tail -50

# Check if probe endpoints are hitting errors
kubectl describe pod -n orchestrator <pod-name> | grep -A10 "Liveness\|Readiness"
```

**Common Causes:**
- Application not started correctly (see logs)
- Probe endpoint not implemented
- Probe timeout too short for startup
- Application listening on wrong port

**Recovery:** Check logs and increase probe `initialDelaySeconds` if needed.

---

### Problem: "Service endpoints not available"

```bash
# Check service details
kubectl get svc -n orchestrator
kubectl describe svc orchestrator-api -n orchestrator

# Verify endpoints exist
kubectl get endpoints -n orchestrator

# Check DNS resolution
kubectl run -n orchestrator --rm -it debug --image=busybox:1.28 \
  -- sh -c 'nslookup orchestrator-api.orchestrator.svc.cluster.local'
```

**Common Causes:**
- No running pods (traffic targets)
- Pod not ready yet
- Service selector not matching pod labels
- Pod network connectivity issues

**Recovery:** Verify pods are running and service selectors match pod labels.

---

## 📝 Post-Installation Checklist

After successful installation, verify:

- [ ] All pods are in `Running` state:
  ```bash
  kubectl get pods -n orchestrator
  ```

- [ ] Service has endpoints:
  ```bash
  kubectl get endpoints -n orchestrator
  ```

- [ ] API is healthy:
  ```bash
  kubectl port-forward -n orchestrator svc/orchestrator-api 8080:8080
  curl http://localhost:8080/healthz
  ```

- [ ] Kafka connectivity confirmed:
  ```bash
  kubectl exec -n orchestrator <pod-name> -- env | grep KAFKA
  ```

- [ ] Redis connectivity confirmed:
  ```bash
  kubectl exec -n orchestrator <pod-name> -- env | grep REDIS
  ```

- [ ] No error messages in logs:
  ```bash
  kubectl logs -n orchestrator <pod-name> | grep -i error
  ```

- [ ] Resource limits reasonable:
  ```bash
  kubectl top pods -n orchestrator
  ```

---

## � Azure-Specific Guidance

This section covers Azure AKS-specific configuration and best practices.

### Azure Architecture

- **Kafka**: Deployed in AKS under a dedicated nodepool
- **Redis**: Either in-cluster or Azure Cache for Redis (optional)
- **API & Consumer**: Deployed in application nodepool
- **Container Registry**: Azure Container Registry (ACR)

### Files Overview

- **values-dev.yaml** - Development environment configuration (2 replicas, smaller resources)
- **values.yaml** - Default Helm values

### Azure Prerequisites

Ensure Kafka and Redis are already deployed in your AKS cluster:

```bash
# Check if Kafka is running
kubectl get pods -n kafka
kubectl get svc -n kafka

# Check if Redis is running (optional)
kubectl get pods -n redis
kubectl get svc -n redis
```

**Expected Kafka service name**: `kafka-broker-service` in `kafka` namespace

### Azure-Specific Helm Values

The values files are configured for in-cluster Kafka:

```yaml
KAFKA_BROKERS: "kafka-broker-service.kafka:9092"
REDIS_ADDR: "redis-service.redis:6379"  # or Azure managed Redis
```

If using **Azure Cache for Redis** instead of in-cluster:
- Edit `values-dev.yaml`
- Update `REDIS_ADDR` to your Azure Redis endpoint
- Update `REDIS_TLS_ENABLED` to `"true"`

### Environment-Specific Configurations

#### Development (values-dev.yaml)
- 2 replicas for API
- Single replica for status-consumer
- Smaller resource limits (500m CPU, 512Mi memory)
- Domain: `dev.service.thinklabs.ai`
- Kafka in same cluster

### Azure Container Registry (ACR) - Image Tagging Strategy

For AKS deployment, use proper version tags with your ACR:

```bash
# Development builds
docker build -f Dockerfile.orchestrator-api -t thinklabsacr.azurecr.io/orchestrator-api:1.0.0-dev .

# Production releases
docker build -f Dockerfile.orchestrator-api -t thinklabsacr.azurecr.io/orchestrator-api:1.0.0 .

# Push to ACR
az acr login --name thinklabsacr
docker push thinklabsacr.azurecr.io/orchestrator-api:1.0.0
```

Always update `values-*.yaml` with specific tags, **not `latest`**.

### Azure Cache for Redis (Optional)

If you prefer managed Redis instead of in-cluster:

#### Step 1: Create Azure Redis Cache
```bash
az redis create \
  --resource-group rg-mlops \
  --name thinklabs-redis \
  --location westus2 \
  --sku Basic
```

#### Step 2: Update values file
```yaml
env:
  REDIS_ADDR: "thinklabs-redis.redis.cache.windows.net:6380"
  REDIS_PASSWORD: ""  # Set via secret
  REDIS_TLS_ENABLED: "true"
```

#### Step 3: Create secret
```bash
REDIS_KEY=$(az redis list-keys --name thinklabs-redis --resource-group rg-mlops --query primaryKey -o tsv)

kubectl create secret generic redis-credentials \
  --from-literal=password="${REDIS_KEY}" \
  -n orchestrator
```

### Azure Security Best Practices

1. **Network Policies**: Restrict traffic between pods and namespaces
2. **RBAC**: Use principle of least privilege
3. **TLS**: Always use `https` with proper certificates
4. **Secrets**: Never commit real secrets; use Kubernetes secrets or Azure Key Vault
5. **Image Pull**: Use service principals for ACR authentication
6. **Kafka**: Consider enabling authentication/authorization if not in isolated network
7. **Azure Key Vault**: Store sensitive values in Key Vault, not in Git

### Migration from Helm Values

If updating existing Azure deployment:
```bash
# Get current values
helm get values thinklabs -n orchestrator > current-values.yaml

# Merge with new values (Kafka broker address might change)
helm upgrade thinklabs . \
  -f values-dev.yaml \
  -n orchestrator
```

---

## �🚀 Next Steps

After successful verification:

1. **Deploy Status Consumer** (if needed):
   ```bash
   helm install status-consumer charts/status-consumer \
     --namespace orchestrator
   ```

2. **Start Using the API**:
   ```bash
   # Get API endpoint
   kubectl get svc -n orchestrator

   # Test inference endpoint
   curl -X POST http://<api-ip>:8080/v1/inference \
     -H "Content-Type: application/json" \
     -d '{"model":"test","inputs":{}}'
   ```

3. **Set up Monitoring**:
   - Configure Prometheus scraping
   - Set up Grafana dashboards
   - View logs with kubectl or centralized logging

4. **Production Hardening**:
   - Configure network policies
   - Set up pod security policies
   - Enable audit logging
   - Configure backup/restore strategies

---

## 🔗 Related Documentation

- **[TESTING.md](TESTING.md)** - Testing architecture and patterns
- **[tests/README.md](tests/README.md)** - In-depth testing guide
- **[README.md](README.md)** - Project overview
- **[docs/ORCHESTRATOR_KAFKA_IN_CLUSTER_GUIDE.md](docs/ORCHESTRATOR_KAFKA_IN_CLUSTER_GUIDE.md)** - In-cluster Kafka architecture and deployment
