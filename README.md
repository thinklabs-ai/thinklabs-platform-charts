# 🚀 ThinkLabs Platform Charts - Helm Installation Guide

Comprehensive installation and verification guide for deploying ThinkLabs Platform services on Azure Kubernetes Service (AKS) using Helm.

---

## 📋 Overview

This repository contains Helm charts for deploying multiple services that compose the ThinkLabs platform:

| Service | Purpose | Container Registry |
|---------|---------|-------------------|
| **Document Generator Service** | Document generation microservice | Azure Container Registry (ACR) |
| **Orchestrator API & Status Consumer** | MLOps orchestration and workflow management | Azure Container Registry (ACR) |
| **Supporting Infrastructure** | Kafka, Redis, PostgreSQL, Observability, Monitoring | Community/Public registries |

---

## 🗂️ Chart Overview

| Chart | Purpose | Version | Dependencies |
|-------|---------|---------|--------------|
| **document-generator-service** | Document generation microservice | 0.1.0 | None |
| **orchestrator-api** | MLOps Orchestrator API & status-consumer | 0.1.0 | Kafka, Redis, OTEL |
| **kafka** | Apache Kafka single broker (KRaft mode) | 0.1.0 | None |
| **kafka-ui** | Kafka Web UI Dashboard | 0.1.0 | Kafka |
| **postgres** | PostgreSQL Database | 0.1.0 | None |
| **redis** | Redis In-Memory Cache | 0.1.0 | None |
| **observability** | Jaeger + OpenTelemetry Collector | 0.1.0 | None |
| **kube-prometheus-stack** | Prometheus + Grafana + Alertmanager | 0.1.0 | Prometheus Community Charts |
| **mlflow** | MLflow Model Tracking (Placeholder) | 0.1.0 | None |

---

## 📋 Prerequisites

Before starting, ensure you have the following tools installed and configured:

### Required Tools
- **Azure CLI** (`az`) - [Install Guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- **kubectl** (1.20+) - [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm 3** - [Install Guide](https://helm.sh/docs/intro/install/)
- **curl** (for API testing)
- **jq** (optional, for JSON parsing)

### Required Azure Resources
- ✅ AKS Cluster (running and accessible)
- ✅ Resource Group (where your AKS cluster resides)
- ✅ Container Registry (Azure Container Registry)
- ✅ Storage Account (for Document Generator Service)
- ✅ Managed Identity (linked to AKS cluster for Workload Identity)

### Verify Cluster Connection
```bash
# Check cluster info
kubectl cluster-info
kubectl get nodes

# List available contexts
kubectl config get-contexts

# Verify permissions
kubectl auth can-i create deployments --all-namespaces
```

---

## 🚀 Installation Order & Dependencies

**Recommended installation sequence:**

```
1. postgres (database foundation)
   ↓
2. redis (cache layer)
   ↓
3. kafka (message queue)
   ↓
4. kafka-ui (kafka monitoring - optional)
   ↓
5. observability (jaeger + otel)
   ↓
6. kube-prometheus-stack (monitoring - optional)
   ↓
7. document-generator-service (application)
   ↓
8. orchestrator-api (MLOps orchestration)
   ↓
9. mlflow (optional - ML tracking)
```

---

# Part 1: Document Generator Service Installation

## 🔧 Document Generator Service - Setup Instructions

### Prerequisites for Document Generator Service

You'll need to gather the following information (export as environment variables):

```bash
# Your Azure subscription and resource details
export SUBSCRIPTION_ID="<your-subscription-id>"
export RESOURCE_GROUP="<your-resource-group-name>"
export AKS_CLUSTER_NAME="<your-aks-cluster-name>"
export LOCATION="<your-azure-region>"  # e.g., uswest2, eastus

# Your storage account and container details
export STORAGE_ACCOUNT_NAME="<your-storage-account-name>"
export STORAGE_CONTAINER="<your-container-name>"  # e.g., reports

# Your namespace and service account names
export NAMESPACE="document-generator-service"
export SERVICE_ACCOUNT_NAME="document-generator-service-sa"

# Your Managed Identity details
export MANAGED_IDENTITY_NAME="<your-managed-identity-name>"
export MANAGED_IDENTITY_CLIENT_ID="<your-managed-identity-client-id>"
```

### Step 1: Configure Azure CLI

```bash
# Login to Azure
az login

# Set the subscription
az account set --subscription ${SUBSCRIPTION_ID}

# Set default resource group and location
az configure --defaults group=${RESOURCE_GROUP} location=${LOCATION}
```

### Step 2: Configure kubectl for AKS

```bash
# Get AKS cluster credentials
az aks get-credentials \
  --resource-group ${RESOURCE_GROUP} \
  --name ${AKS_CLUSTER_NAME} \
  --overwrite-existing
```

### Step 3: Create Namespace

```bash
# Create the namespace for the application
kubectl create namespace ${NAMESPACE}

# Verify namespace creation
kubectl get namespace ${NAMESPACE}
```

---

## 🔑 Create ACR Credentials Secret

The application pulls images from a private ACR registry. You need to create a Kubernetes secret with your ACR credentials.

### Step 4: Set ACR Credentials as Environment Variables

```bash
# REQUIRED: Your ACR registry login server
export ACR_LOGIN_SERVER="<your-acr-login-server>"  # e.g., yourregistry.azurecr.io

# REQUIRED: Your ACR username (from Azure Portal > Container Registries > Access Keys)
export ACR_USERNAME="<your-acr-username>"

# REQUIRED: Your ACR password (from Azure Portal > Container Registries > Access Keys)
export ACR_PASSWORD="<your-acr-password>"

# REQUIRED: Your email address
export DOCKER_EMAIL="<your-email>"  # e.g., noreply@company.com
```

### Step 5: Create the Docker Registry Secret in Kubernetes

```bash
# Create the docker-registry secret in your namespace
kubectl create secret docker-registry acr-creds \
  --docker-server=${ACR_LOGIN_SERVER} \
  --docker-username=${ACR_USERNAME} \
  --docker-password=${ACR_PASSWORD} \
  --docker-email=${DOCKER_EMAIL} \
  --namespace=${NAMESPACE}
```

### Step 6: Verify the Secret was Created

```bash
# List secrets in the namespace
kubectl get secrets -n ${NAMESPACE}

# Describe the acr-creds secret
kubectl describe secret acr-creds -n ${NAMESPACE}
```

---

## 🏗️ Infrastructure Setup (One-time)

### Verify Storage Account

```bash
# List storage accounts
az storage account list --resource-group ${RESOURCE_GROUP} --query "[].name"

# If your storage account doesn't exist, create it:
az storage account create \
  --name ${STORAGE_ACCOUNT_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --location ${LOCATION} \
  --sku Standard_LRS \
  --kind StorageV2
```

### Create a Container in Storage Account

```bash
# Get storage account key
STORAGE_KEY=$(az storage account keys list \
  --account-name ${STORAGE_ACCOUNT_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --query '[0].value' -o tsv)

# Create container
az storage container create \
  --name ${STORAGE_CONTAINER} \
  --account-name ${STORAGE_ACCOUNT_NAME} \
  --account-key ${STORAGE_KEY}

# Verify
az storage container list \
  --account-name ${STORAGE_ACCOUNT_NAME} \
  --account-key ${STORAGE_KEY}
```

### Managed Identity and RBAC Setup

```bash
# Create Managed Identity
az identity create \
  --name ${MANAGED_IDENTITY_NAME} \
  --resource-group ${RESOURCE_GROUP}

# Get the Managed Identity details
IDENTITY_ID=$(az identity show \
  --name ${MANAGED_IDENTITY_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --query 'id' -o tsv)

MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
  --name ${MANAGED_IDENTITY_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --query 'clientId' -o tsv)

echo "Managed Identity ID: $IDENTITY_ID"
echo "Client ID: $MANAGED_IDENTITY_CLIENT_ID"
```

### Assign Storage Account Access

```bash
# Get Storage Account Resource ID
STORAGE_ACCOUNT_ID=$(az storage account show \
  --name ${STORAGE_ACCOUNT_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --query 'id' -o tsv)

# Assign "Storage Blob Data Contributor" role
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee ${MANAGED_IDENTITY_CLIENT_ID} \
  --scope ${STORAGE_ACCOUNT_ID}

# Verify role assignment
az role assignment list \
  --assignee ${MANAGED_IDENTITY_CLIENT_ID}
```

### Create Workload Identity Federation

```bash
# Get AKS OIDC Issuer URL
AKS_OIDC_ISSUER=$(az aks show \
  --resource-group ${RESOURCE_GROUP} \
  --name ${AKS_CLUSTER_NAME} \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

echo "AKS OIDC Issuer: $AKS_OIDC_ISSUER"

# Create federated identity credential
az identity federated-credential create \
  --name ${MANAGED_IDENTITY_NAME}-fed \
  --identity-name ${MANAGED_IDENTITY_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --issuer ${AKS_OIDC_ISSUER} \
  --subject "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}" \
  --audience api://AzureADTokenExchange
```

---

## 📦 Helm Installation - Document Generator Service

### Prerequisites for Helm Installation

Before installing the Helm chart, ensure:
1. ✅ Namespace has been created
2. ✅ **`acr-creds` secret has been created**
3. ✅ Managed Identity has been set up with Workload Identity Federation
4. ✅ Storage account and container exist

### Installation

```bash
# Install the helm chart
helm install document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE} \
  --set image.repository=${ACR_LOGIN_SERVER}/thinklabs-document-generator-service-x86 \
  --set azure.storageAccount=${STORAGE_ACCOUNT_NAME} \
  --set azure.container=${STORAGE_CONTAINER} \
  --set "serviceAccount.annotations.azure\.workload\.identity/client-id"=${MANAGED_IDENTITY_CLIENT_ID}
```

### Verify Deployment

```bash
# Check Helm release
helm list --namespace ${NAMESPACE}

# Check deployment status
kubectl get deployment -n ${NAMESPACE}
kubectl get pods -n ${NAMESPACE}
kubectl describe pod -n ${NAMESPACE} <pod-name>

# Check logs
kubectl logs -n ${NAMESPACE} -l app=document-generator-service
```

### Upgrade the Release

```bash
# Upgrade with new image tag
helm upgrade document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE} \
  --set image.tag=<new-tag>
```

---

# Part 2: Orchestrator API Installation

## 🔧 Orchestrator API - Installation Steps

### Quick Start

```bash
# Prerequisites Check
kubectl version --client
helm version
curl --version
kubectl cluster-info
```

### Option A: Installation with Default Values

#### Dry-Run First

```bash
# Validate the chart without installing
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  --create-namespace \
  --dry-run \
  --debug
```

#### Perform Actual Installation

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
```

---

## ✅ Orchestrator API - Verification Suite

Four comprehensive verification scripts are provided in `tests/orchestrator/helm/`:

### 1. **verify-helm-install.sh** - Main Verification

```bash
./tests/orchestrator/helm/verify-helm-install.sh [NAMESPACE] [RELEASE]

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

---

### 2. **component-health-check.sh** - Component Configuration Validation

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

---

### 3. **integration-tests.sh** - Connectivity and API Testing

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

---

### 4. **e2e-tests.sh** - End-to-End Testing

```bash
./tests/orchestrator/helm/e2e-tests.sh [NAMESPACE] [RELEASE] [DRY_RUN] [CLEANUP]

# Examples:
./tests/orchestrator/helm/e2e-tests.sh orchestrator orchestrator true false   # Dry-run, no cleanup
./tests/orchestrator/helm/e2e-tests.sh orchestrator orchestrator false true   # Full test + cleanup
```

**Test Stages:**
1. **Pre-flight Checks** - Prerequisites and cluster validation
2. **Helm Installation** - Install or dry-run the chart
3. **Deployment Verification** - Wait for pod readiness
4. **Component Tests** - Run component health checks
5. **Integration Tests** - Test connectivity and APIs
6. **Cleanup** - Optional cleanup and summary report

---

## 📊 Test Workflow Recommendations

### Scenario 1: Pre-Installation Validation (< 10 min)

```bash
./tests/orchestrator/helm/e2e-tests.sh my-namespace orchestrator true false
```

### Scenario 2: Quick Verification After Install (5-10 min)

```bash
./tests/orchestrator/helm/verify-helm-install.sh my-namespace orchestrator
```

### Scenario 3: Comprehensive Health Check (15-20 min)

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

### Scenario 4: Production Deployment (20-30 min)

```bash
# 1. Dry-run first
./tests/orchestrator/helm/e2e-tests.sh my-prod orchestrator true false

# 2. Perform actual installation
helm install orchestrator charts/orchestrator-api \
  --namespace my-prod \
  --create-namespace \
  -f prod-values.yaml

# 3. Run full verification suite
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

## 🛠️ Orchestrator API - Troubleshooting Guide

### Problem: "Helm chart linting failed"

```bash
# Check what the error is
helm lint charts/orchestrator-api

# Inspect the chart structure
ls -la charts/orchestrator-api/
cat charts/orchestrator-api/Chart.yaml
```

**Common Causes:**
- Invalid YAML syntax (indentation, quotes)
- Missing required fields in `Chart.yaml`
- Invalid Helm template syntax

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
```

**Common Causes:**
- Kafka service not running in cluster
- Wrong Kafka broker address in environment variables
- Network policy blocking traffic

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
```

**Common Causes:**
- Redis service not running
- Wrong host/port in environment variables
- Network policy blocking access

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
```

**Common Causes:**
- Application not started correctly (see logs)
- Probe endpoint not implemented
- Probe timeout too short for startup
- Application listening on wrong port

---

## 📝 Orchestrator API - Post-Installation Checklist

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

- [ ] Kafka connectivity confirmed
- [ ] Redis connectivity confirmed
- [ ] No error messages in logs
- [ ] Resource limits reasonable

---

## 🔍 General Troubleshooting

### Check Image Pull Issues

```bash
# Describe the pod to see events
kubectl describe pod -n <namespace> <pod-name>

# Check if image is being pulled
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Check Workload Identity

```bash
# Verify service account has the correct annotation
kubectl get serviceaccount -n <namespace> \
  <your-service-account-name> -o yaml

# Check pod identity binding
kubectl describe pod -n <namespace> <pod-name> | grep azure.workload.identity
```

### Test Azure Connectivity

```bash
# Execute into the pod
kubectl exec -it -n <namespace> <pod-name> -- /bin/bash

# Inside the pod, test Azure access
python -c "from azure.identity import DefaultAzureCredential; print(DefaultAzureCredential().get_token('https://storage.azure.com'))"
```

### View Application Logs

```bash
# Stream logs
kubectl logs -f -n <namespace> -l app=<app-name>

# View logs from a specific pod
kubectl logs -n <namespace> <pod-name>
```

---

## 🔄 Helm Operations

### Upgrade a Release

```bash
# Upgrade with new image tag
helm upgrade <release-name> ./charts/<chart-name> \
  --namespace <namespace> \
  --set image.tag=<new-tag>
```

### Uninstall a Release

```bash
# Remove the Helm release
helm uninstall <release-name> \
  --namespace <namespace>

# To delete the namespace as well:
kubectl delete namespace <namespace>
```

---

## 🔐 Security Best Practices

1. **Never commit secrets to the repository**
   - ACR credentials are created as a secret in the cluster
   - Managed Identity handles Azure authentication without storing keys

2. **Use Workload Identity Federation**
   - Eliminates the need for service principal keys
   - Provides time-limited tokens automatically

3. **Least Privilege Access**
   - Grant only necessary roles to managed identities
   - Review and restrict ACR access

4. **Network Security**
   - Use Azure Private Endpoints for storage account
   - Restrict ACR access to AKS cluster network
   - Implement network policies for pod-to-pod communication

5. **Secret Management**
   - Store sensitive values in Azure Key Vault, not Git
   - Use Kubernetes secrets for runtime values
   - Rotate credentials regularly

---

## 📚 Additional Resources

- [Helm Documentation](https://helm.sh/docs/)
- [Azure Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [Apache Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

---

**Last Updated:** March 2026

For questions or issues, please contact the platform engineering team.
