# 🏗️ Infrastructure Installation Guide

Complete step-by-step instructions for installing all infrastructure and platform services on Azure Kubernetes Service (AKS).

**Last Updated:** March 2026

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [PostgreSQL Installation](#postgresql-installation)
4. [Redis Installation](#redis-installation)
5. [Kafka Installation](#kafka-installation)
6. [Kafka UI Installation](#kafka-ui-installation)
7. [Observability Stack Installation](#observability-stack-installation)
8. [Kube Prometheus Stack Installation](#kube-prometheus-stack-installation)
9. [MLflow Installation](#mlflow-installation)
10. [TensorBoard Installation](#tensorboard-installation)
11. [Complete Installation Script](#complete-installation-script)
12. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

- **Azure CLI** (`az`) - [Install Guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- **kubectl** - [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm 3** - [Install Guide](https://helm.sh/docs/intro/install/)

### Required Azure Resources

- ✅ AKS Cluster (running and accessible)
- ✅ Resource Group (where your AKS cluster resides)
- ✅ Storage Account(s) (for artifacts and logs)
- ✅ Managed Identities (for workload identity)

### Node Pool Requirements

Ensure your AKS cluster has node pools with the following labels:

```bash
# Check existing node labels
kubectl get nodes --show-labels

# Required labels:
# - workload-type: general      (for general workloads)
# - workload-type: database     (for PostgreSQL - optional, can use general)
```

If labels are missing, add them:

```bash
# Add label to a node pool
kubectl label nodes <node-name> workload-type=general
```

### Pre-Installation Checklist

- ✅ AKS cluster is running and accessible
- ✅ kubectl is configured and authenticated
- ✅ Helm 3.x is installed
- ✅ Available storage classes: `managed-csi`, `managed-csi-premium`
- ✅ Sufficient cluster resources (recommend: 8+ CPU cores, 16GB+ RAM)

---

## Environment Setup

### Step 1: Configure Azure CLI

```bash
# Login to Azure
az login

# Set your subscription (find it in Azure Portal or use az account list)
export SUBSCRIPTION_ID="<your-subscription-id>"
az account set --subscription ${SUBSCRIPTION_ID}

# Set environment variables
export RESOURCE_GROUP="<your-resource-group-name>"
export AKS_CLUSTER_NAME="<your-aks-cluster-name>"
export LOCATION="<your-azure-region>"  # e.g., eastus, westus2

# Set defaults for easier commands
az configure --defaults group=${RESOURCE_GROUP} location=${LOCATION}
```

### Step 2: Configure kubectl

```bash
# Get AKS cluster credentials
az aks get-credentials \
  --resource-group ${RESOURCE_GROUP} \
  --name ${AKS_CLUSTER_NAME} \
  --overwrite-existing

# Verify connection
kubectl get nodes
kubectl get storageclass
```

### Step 3: Verify Available Storage Classes

```bash
# List available storage classes
kubectl get storageclass

# You should see:
# - managed-csi (Standard)
# - managed-csi-premium (Premium)
# - azurefile-csi (Azure Files)

# If not available, enable CSI drivers on your AKS cluster:
az aks update --enable-managed-identity -g ${RESOURCE_GROUP} -n ${AKS_CLUSTER_NAME} \
  --enable-azure-csi-storage-drivers
```

---

## PostgreSQL Installation

PostgreSQL serves as the primary relational database for the platform.

### Prerequisites

- Storage class available: `managed-csi-premium`
- Node pool labeled: `workload-type: database` (or `general`)

### Step 1: Create Namespace and Secret

```bash
# Set PostgreSQL credentials
export POSTGRES_NAMESPACE="postgres"
export POSTGRES_DB="appdb"
export POSTGRES_USER="appuser"
export POSTGRES_PASSWORD="$(openssl rand -base64 32)"  # Generate secure password

# Create namespace
kubectl create namespace ${POSTGRES_NAMESPACE}

# Create secret with PostgreSQL credentials
kubectl create secret generic postgres-akv-secret \
  --from-literal=POSTGRES_DB=${POSTGRES_DB} \
  --from-literal=POSTGRES_USER=${POSTGRES_USER} \
  --from-literal=POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  -n ${POSTGRES_NAMESPACE}

# Verify secret
kubectl describe secret postgres-akv-secret -n ${POSTGRES_NAMESPACE}

# Save credentials for later use
cat > postgres-credentials.txt << EOF
Database Name: ${POSTGRES_DB}
Username: ${POSTGRES_USER}
Password: ${POSTGRES_PASSWORD}
EOF
echo "✓ Credentials saved to postgres-credentials.txt"
```

### Step 2: Install PostgreSQL

```bash
# Install PostgreSQL Helm chart
helm install postgres ./charts/postgres \
  --namespace ${POSTGRES_NAMESPACE} \
  --values ./charts/postgres/values.yaml

# Monitor installation
kubectl rollout status statefulset/postgres-postgres -n ${POSTGRES_NAMESPACE}

# Check pod status
kubectl get pods -n ${POSTGRES_NAMESPACE}
kubectl get pvc -n ${POSTGRES_NAMESPACE}
```

### Step 3: Verify Installation

```bash
# Get PostgreSQL connection details
POSTGRES_SERVICE_IP=$(kubectl get svc -n ${POSTGRES_NAMESPACE} postgres-postgres \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip // .spec.clusterIP}')

echo "PostgreSQL Details:"
echo "  Host: ${POSTGRES_SERVICE_IP}"
echo "  Port: 5432"
echo "  Database: ${POSTGRES_DB}"
echo "  Username: ${POSTGRES_USER}"

# Test connection from a pod (if load balancer IP is assigned)
kubectl run postgres-client --image=postgres:16 --rm -it --restart=Never \
  -n ${POSTGRES_NAMESPACE} \
  -- psql -h ${POSTGRES_SERVICE_IP} -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "SELECT version();"
```

### Step 4: Update Values (Optional)

Edit `charts/postgres/values.yaml` to customize:

```yaml
persistence:
  size: 128Gi           # Adjust storage size based on needs
  storageClass: managed-csi-premium

service:
  type: LoadBalancer    # Use LoadBalancer for external access
  # OR use ClusterIP for internal-only access
  # type: ClusterIP

resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "2"
    memory: "4Gi"

nodeSelector:
  workload-type: database  # Or 'general' if database label not available
```

---

## Redis Installation

Redis provides in-memory caching for the platform.

### Prerequisites

- Storage class available: `managed-csi`
- Node pool labeled: `workload-type: general`

### Step 1: Install Redis

```bash
# Set Redis namespace
export REDIS_NAMESPACE="redis"

# Redis chart auto-creates namespace, but we can create it explicitly
kubectl create namespace ${REDIS_NAMESPACE}

# Install Redis Helm chart
helm install redis ./charts/redis \
  --namespace ${REDIS_NAMESPACE} \
  --values ./charts/redis/values.yaml

# Monitor installation
kubectl rollout status deployment/redis-redis -n ${REDIS_NAMESPACE}

# Check pod status
kubectl get pods -n ${REDIS_NAMESPACE}
kubectl get pvc -n ${REDIS_NAMESPACE}
```

### Step 2: Verify Installation

```bash
# Get Redis connection details
REDIS_HOST=$(kubectl get svc -n ${REDIS_NAMESPACE} redis \
  -o jsonpath='{.spec.clusterIP}')
REDIS_PORT=$(kubectl get svc -n ${REDIS_NAMESPACE} redis \
  -o jsonpath='{.spec.ports[0].port}')

echo "Redis Details:"
echo "  Host: ${REDIS_HOST}"
echo "  Port: ${REDIS_PORT}"
echo "  Connection String: redis://${REDIS_HOST}:${REDIS_PORT}/0"

# Test Redis connection
kubectl run redis-client --image=redis:7.2 --rm -it --restart=Never \
  -n ${REDIS_NAMESPACE} \
  -- redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} PING

# Expected output: PONG
```

### Step 3: Update Values (Optional)

Edit `charts/redis/values.yaml` to customize:

```yaml
redis:
  persistence:
    enabled: true
    size: 5Gi              # Adjust based on cache needs
    storageClassName: managed-csi

  auth:
    enabled: false         # Enable for production
    password: ""           # Set a secure password if enabled

  service:
    type: ClusterIP        # Keep as internal-only
    port: 6379

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 300m
    memory: 256Mi
```

---

## Kafka Installation

Kafka serves as the message broker for event streaming, using KRaft mode (no Zookeeper).

### Prerequisites

- Storage class available: `managed-csi`
- Node pool labeled: `workload-type: general`

### Step 1: Create Namespace and Secret

```bash
# Set Kafka namespace
export KAFKA_NAMESPACE="kafka"

# Create namespace
kubectl create namespace ${KAFKA_NAMESPACE}

# Generate Kafka cluster ID
export KAFKA_CLUSTER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
echo "Kafka Cluster ID: ${KAFKA_CLUSTER_ID}"

# Create secret with cluster ID
kubectl create secret generic kafka-secret \
  --from-literal=KAFKA_CLUSTER_ID=${KAFKA_CLUSTER_ID} \
  -n ${KAFKA_NAMESPACE}

# Verify secret
kubectl describe secret kafka-secret -n ${KAFKA_NAMESPACE}
```

### Step 2: Install Kafka

```bash
# Install Kafka Helm chart
helm install kafka ./charts/kafka \
  --namespace ${KAFKA_NAMESPACE} \
  --values ./charts/kafka/values.yaml

# Monitor installation
kubectl rollout status statefulset/kafka-kafka -n ${KAFKA_NAMESPACE}

# Check pod and PVC status
kubectl get pods -n ${KAFKA_NAMESPACE}
kubectl get pvc -n ${KAFKA_NAMESPACE}

# View Kafka pod logs
kubectl logs -f -n ${KAFKA_NAMESPACE} kafka-0
```

### Step 3: Verify Installation

```bash
# Get Kafka bootstrap server
KAFKA_HOST=$(kubectl get svc -n ${KAFKA_NAMESPACE} kafka-kafka \
  -o jsonpath='{.spec.clusterIP}')
KAFKA_PORT=$(kubectl get svc -n ${KAFKA_NAMESPACE} kafka-kafka \
  -o jsonpath='{.spec.ports[0].port}')

echo "Kafka Bootstrap Server:"
echo "  Host: ${KAFKA_HOST}"
echo "  Port: ${KAFKA_PORT}"
echo "  Bootstrap Address: ${KAFKA_HOST}:${KAFKA_PORT}"

# Create a test pod to verify Kafka connectivity
kubectl run kafka-test --image=thinklabsinternalacrdev.azurecr.io/infra/kafka/kafka:4.2.0 \
  --rm -it --restart=Never \
  -n ${KAFKA_NAMESPACE} \
  -- bash

# Inside the test pod, run:
# kafka-broker-api-versions.sh --bootstrap-server kafka-kafka:9092
```

### Step 4: Update Values (Optional)

Edit `charts/kafka/values.yaml` to customize:

```yaml
persistence:
  size: 100Gi            # Adjust storage size based on throughput
  storageClass: managed-csi

service:
  type: ClusterIP        # Keep as internal
  port: 9092             # Client port

resources:
  requests:
    cpu: "1"
    memory: "2Gi"
  limits:
    cpu: "2"
    memory: "4Gi"

kraft:
  clusterId: ""          # Auto-populated from secret
```

---

## Kafka UI Installation

Kafka UI provides a web dashboard for monitoring and managing Kafka.

### Prerequisites

- Kafka must be installed and running
- Node pool labeled: `workload-type: general`

### Step 1: Install Kafka UI

```bash
# Set Kafka UI namespace
export KAFKAUI_NAMESPACE="kafka-ui"
export KAFKA_NAMESPACE="kafka"

# Create namespace
kubectl create namespace ${KAFKAUI_NAMESPACE}

# Get Kafka bootstrap servers (from previous installation)
export KAFKA_BOOTSTRAP_SERVERS="kafka-kafka.${KAFKA_NAMESPACE}.svc.cluster.local:9092"

# Install Kafka UI Helm chart
helm install kafka-ui ./charts/kafka-ui \
  --namespace ${KAFKAUI_NAMESPACE} \
  --set kafka.bootstrapServers=${KAFKA_BOOTSTRAP_SERVERS} \
  --set kafka.clusterName="thinklabs-dev-kafka" \
  --values ./charts/kafka-ui/values.yaml

# Monitor installation
kubectl rollout status deployment/kafka-ui -n ${KAFKAUI_NAMESPACE}

# Check pod status
kubectl get pods -n ${KAFKAUI_NAMESPACE}
```

### Step 2: Verify Installation and Access

```bash
# Get Kafka UI service details
KAFKAUI_IP=$(kubectl get svc -n ${KAFKAUI_NAMESPACE} kafka-ui \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip // .spec.clusterIP}')
KAFKAUI_PORT=$(kubectl get svc -n ${KAFKAUI_NAMESPACE} kafka-ui \
  -o jsonpath='{.spec.ports[0].port}')

echo "Kafka UI Access:"
echo "  Service IP: ${KAFKAUI_IP}"
echo "  Port: ${KAFKAUI_PORT}"

# Option 1: Port-forward for local access
kubectl port-forward -n ${KAFKAUI_NAMESPACE} svc/kafka-ui 8080:8080
# Access at: http://localhost:8080

# Option 2: If LoadBalancer is configured
# Access at: http://${KAFKAUI_IP}:${KAFKAUI_PORT}
```

### Step 3: Configure Load Balancer (Optional)

To expose Kafka UI via internal load balancer:

```bash
# Edit values.yaml
helm upgrade kafka-ui ./charts/kafka-ui \
  --namespace ${KAFKAUI_NAMESPACE} \
  --set service.loadBalancer.enabled=true \
  --set service.loadBalancer.port=80

# Verify LoadBalancer service
kubectl get svc -n ${KAFKAUI_NAMESPACE}
```

---

## Observability Stack Installation

The observability stack includes Jaeger (distributed tracing) and OpenTelemetry Collector.

### Prerequisites

- Node pool labeled: `workload-type: general`
- No persistent storage required for basic setup

### Step 1: Install Observability Stack

```bash
# Set Observability namespace
export OBSERVABILITY_NAMESPACE="observability"

# Observability chart auto-creates namespace, but we can create explicitly
kubectl create namespace ${OBSERVABILITY_NAMESPACE}

# Install Observability Helm chart
helm install observability ./charts/observability \
  --namespace ${OBSERVABILITY_NAMESPACE} \
  --values ./charts/observability/values.yaml

# Monitor installation
kubectl rollout status deployment/jaeger -n ${OBSERVABILITY_NAMESPACE}
kubectl rollout status deployment/otel-collector -n ${OBSERVABILITY_NAMESPACE}

# Check pod status
kubectl get pods -n ${OBSERVABILITY_NAMESPACE}
```

### Step 2: Verify Installation

```bash
# Get service endpoints
echo "Jaeger UI:"
kubectl get svc -n ${OBSERVABILITY_NAMESPACE} jaeger

echo "OTEL Collector:"
kubectl get svc -n ${OBSERVABILITY_NAMESPACE} otel-collector

# Port-forward to access Jaeger UI locally
kubectl port-forward -n ${OBSERVABILITY_NAMESPACE} svc/jaeger 16686:16686

# Access Jaeger UI at: http://localhost:16686
```

### Step 3: Configure Application Tracing

To send traces from your applications:

```bash
# Get OTEL Collector endpoints
OTEL_GRPC_ENDPOINT="http://otel-collector.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:4317"
OTEL_HTTP_ENDPOINT="http://otel-collector.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:4318"

# Set environment variables in your application:
export OTEL_EXPORTER_OTLP_ENDPOINT=${OTEL_GRPC_ENDPOINT}
export OTEL_TRACES_EXPORTER=otlp
export OTEL_SERVICE_NAME="your-app-name"

# Or via Helm values for your application:
# - name: OTEL_EXPORTER_OTLP_ENDPOINT
#   value: http://otel-collector.observability.svc.cluster.local:4317
```

### Step 4: Jaeger Configuration

The Jaeger deployment is configured with:

```yaml
Storage: Badger (embedded, ephemeral)
OTLP Receiver: Enabled (gRPC and HTTP)
Collector Port: 14250
UI Port: 16686
Trace Export: OTLP to OpenTelemetry Collector
```

For persistent trace storage, update `values.yaml`:

```yaml
jaeger:
  env:
    SPAN_STORAGE_TYPE: "badger"      # Or elasticsearch, cassandra
    BADGER_EPHEMERAL: "false"        # Set to false for persistent storage
```

---

## Kube Prometheus Stack Installation

Complete monitoring stack with Prometheus, Grafana, and Alertmanager.

### Prerequisites

- Storage classes available: `managed-csi`
- Node pool labeled: `workload-type: general`
- Helm repo: `prometheus-community`

### Step 1: Add Helm Repository

```bash
# Add Prometheus Community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Verify repository
helm search repo prometheus-community
```

### Step 2: Create Namespace and Secrets

```bash
# Set Monitoring namespace
export MONITORING_NAMESPACE="monitoring"
export GRAFANA_ADMIN_USER="admin"
export GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 32)"

# Create namespace
kubectl create namespace ${MONITORING_NAMESPACE}

# Create Grafana admin secret
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-user=${GRAFANA_ADMIN_USER} \
  --from-literal=admin-password=${GRAFANA_ADMIN_PASSWORD} \
  -n ${MONITORING_NAMESPACE}

# Save credentials
cat > grafana-credentials.txt << EOF
Grafana Admin User: ${GRAFANA_ADMIN_USER}
Grafana Admin Password: ${GRAFANA_ADMIN_PASSWORD}
EOF
echo "✓ Credentials saved to grafana-credentials.txt"
```

### Step 3: Install Kube Prometheus Stack

```bash
# Install Kube Prometheus Stack
helm install kube-prometheus-stack ./charts/kube-prometheus-stack \
  --namespace ${MONITORING_NAMESPACE} \
  --values ./charts/kube-prometheus-stack/values.yaml \
  --dependency-update

# Monitor installation
kubectl rollout status deployment/kube-prometheus-stack-prometheus -n ${MONITORING_NAMESPACE}
kubectl rollout status deployment/kube-prometheus-stack-grafana -n ${MONITORING_NAMESPACE}

# Check all components
kubectl get all -n ${MONITORING_NAMESPACE}
```

### Step 4: Verify Installation

```bash
# Get service endpoints
kubectl get svc -n ${MONITORING_NAMESPACE}

# Access Prometheus UI
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-prometheus 9090:9090
# Visit: http://localhost:9090

# Access Grafana UI
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-grafana 3000:80
# Visit: http://localhost:3000
# Login with: admin / ${GRAFANA_ADMIN_PASSWORD}

# Access Alertmanager UI
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-alertmanager 9093:9093
# Visit: http://localhost:9093
```

### Step 5: Configure Load Balancer (Optional)

To expose Grafana via internal load balancer:

```bash
# Edit values.yaml to enable load balancer
helm upgrade kube-prometheus-stack ./charts/kube-prometheus-stack \
  --namespace ${MONITORING_NAMESPACE} \
  --set kube-prometheus-stack.grafana.service.loadBalancer.enabled=true \
  --set kube-prometheus-stack.grafana.service.loadBalancer.port=80
```

### Step 6: Key Monitoring Dashboards

Once Grafana is running:

1. **Pre-installed Dashboards:**
   - Kubernetes Cluster Health
   - Kubernetes Pod Resources
   - Kubernetes Deployment Statefulset Daemonset Metrics Statefulsets
   - Prometheus

2. **Import Additional Dashboards:**
   - Visit [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
   - Use dashboard IDs: 1860, 3119, 6417, 12114

---

## MLflow Installation

MLflow provides model tracking, versioning, and management for machine learning workflows.

### Prerequisites

- PostgreSQL must be installed (for metadata storage)
- Storage Account with blob container (for artifact storage)
- Node pool labeled: `workload-type: general`
- Managed Identity with blob storage access

### Step 1: Create Namespace and Secrets

```bash
# Set MLflow namespace
export MLFLOW_NAMESPACE="mlflow"
export POSTGRES_NAMESPACE="postgres"
export POSTGRES_USER="appuser"
export POSTGRES_PASSWORD="<from-postgres-installation>"

# Create namespace
kubectl create namespace ${MLFLOW_NAMESPACE}

# Get PostgreSQL host (internal DNS)
export POSTGRES_HOST="postgres-postgres.${POSTGRES_NAMESPACE}.svc.cluster.local"

# Create MLflow database secret
kubectl create secret generic mlflow-db-secret \
  --from-literal=POSTGRES_USER=${POSTGRES_USER} \
  --from-literal=POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  -n ${MLFLOW_NAMESPACE}

# Verify secret
kubectl describe secret mlflow-db-secret -n ${MLFLOW_NAMESPACE}
```

### Step 2: Create MLflow Database

```bash
# Connect to PostgreSQL and create MLflow database
kubectl run postgres-client --image=postgres:16 --rm -it --restart=Never \
  -n ${POSTGRES_NAMESPACE} \
  -- psql -h postgres-postgres -U appuser -d appdb << EOF
CREATE DATABASE mlflowdb;
GRANT ALL PRIVILEGES ON DATABASE mlflowdb TO appuser;
\l  # List databases to verify
EOF
```

### Step 3: Install MLflow

```bash
# Install MLflow Helm chart
helm install mlflow ./charts/mlflow \
  --namespace ${MLFLOW_NAMESPACE} \
  --set postgres.host=${POSTGRES_HOST} \
  --set postgres.namespace=${POSTGRES_NAMESPACE} \
  --values ./charts/mlflow/values.yaml

# Monitor installation
kubectl rollout status deployment/mlflow -n ${MLFLOW_NAMESPACE}

# Check pod status
kubectl get pods -n ${MLFLOW_NAMESPACE}
```

### Step 4: Verify Installation

```bash
# Get MLflow service details
MLFLOW_IP=$(kubectl get svc -n ${MLFLOW_NAMESPACE} mlflow \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip // .spec.clusterIP}')
MLFLOW_PORT=$(kubectl get svc -n ${MLFLOW_NAMESPACE} mlflow \
  -o jsonpath='{.spec.ports[0].port}')

echo "MLflow Access:"
echo "  IP: ${MLFLOW_IP}"
echo "  Port: ${MLFLOW_PORT}"

# Port-forward for local access
kubectl port-forward -n ${MLFLOW_NAMESPACE} svc/mlflow 5000:5000
# Visit: http://localhost:5000

# Check logs
kubectl logs -f -n ${MLFLOW_NAMESPACE} -l app=mlflow
```

### Step 5: Configure Client

```python
import mlflow

# Set MLflow tracking URI
mlflow.set_tracking_uri("http://mlflow.mlflow.svc.cluster.local:5000")

# Or when running outside cluster
# mlflow.set_tracking_uri("http://mlflow-load-balancer-ip:80")

# Start an experiment
mlflow.set_experiment("my-experiment")

with mlflow.start_run():
    mlflow.log_param("param", 1)
    mlflow.log_metric("accuracy", 0.95)
    mlflow.log_artifact("model.pkl")
```

### Step 6: Configure Azure Blob Artifact Storage

The chart is configured to use Azure Blob Storage. Ensure:

1. **Storage Account Created:**
   ```bash
   export STORAGE_ACCOUNT="thinklabsmlflow"
   export STORAGE_CONTAINER="mlflow-artifacts"
   
   # Verify container exists
   az storage container list --account-name ${STORAGE_ACCOUNT}
   ```

2. **Managed Identity Configured:**
   - Ensure the MLflow service account has managed identity annotation
   - Pod must have RBAC access to blob storage

---

## TensorBoard Installation

TensorBoard provides visualization for machine learning training logs and metrics.

### Prerequisites

- Azure Blob Storage with logs (for BlobFuse mount)
- Node pool labeled: `workload-type: general`
- Managed Identity for blob storage access (optional but recommended)

### Step 1: Create Namespace

```bash
# Set TensorBoard namespace
export TENSORBOARD_NAMESPACE="mlops"

# Create namespace
kubectl create namespace ${TENSORBOARD_NAMESPACE}
```

### Step 2: Upload Sample Logs to Azure Blob

```bash
# Generate sample TensorBoard logs
python generate_tensorboard_logs.py

# Upload to Azure Blob Storage
export STORAGE_ACCOUNT="thinklabsmlflow"
export STORAGE_CONTAINER="mlflow-artifacts"

# Option 1: Using Azure CLI
az storage blob upload-batch \
  -d ${STORAGE_CONTAINER} \
  -s sample_logs \
  --account-name ${STORAGE_ACCOUNT}

# Option 2: Using Azure Storage Explorer (GUI)
# - Download Azure Storage Explorer
# - Connect to your storage account
# - Navigate to the container
# - Upload the sample_logs folder
```

### Step 3: Install TensorBoard

```bash
# Install TensorBoard Helm chart
helm install tensorboard ./charts/tensorboard \
  --namespace ${TENSORBOARD_NAMESPACE} \
  --set blobStorage.accountName=thinklabsmlflow \
  --set blobStorage.containerName=mlflow-artifacts \
  --set blobStorage.logPath=sample_logs \
  --values ./charts/tensorboard/values.yaml

# Monitor installation
kubectl rollout status deployment/tensorboard -n ${TENSORBOARD_NAMESPACE}

# Check pod status
kubectl get pods -n ${TENSORBOARD_NAMESPACE}
```

### Step 4: Verify Installation

```bash
# Get TensorBoard service details
TENSORBOARD_IP=$(kubectl get svc -n ${TENSORBOARD_NAMESPACE} tensorboard \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip // .spec.clusterIP}')
TENSORBOARD_PORT=$(kubectl get svc -n ${TENSORBOARD_NAMESPACE} tensorboard \
  -o jsonpath='{.spec.ports[0].port}')

echo "TensorBoard Access:"
echo "  IP: ${TENSORBOARD_IP}"
echo "  Port: ${TENSORBOARD_PORT}"

# Port-forward for local access
kubectl port-forward -n ${TENSORBOARD_NAMESPACE} svc/tensorboard 6006:6006
# Visit: http://localhost:6006

# Verify blob mount
kubectl exec -it -n ${TENSORBOARD_NAMESPACE} <pod-name> -- ls -la /logs
```

### Step 5: Configure Azure Blob Storage (BlobFuse)

The chart uses BlobFuse to mount Azure Blob Storage. Update `values.yaml`:

```yaml
blobStorage:
  enabled: true
  accountName: "thinklabsmlflow"
  containerName: "mlflow-artifacts"
  logPath: "tensorboard-logs"    # Path within container
  useManagedIdentity: true        # Use managed identity for auth
  # OR use account key (less secure):
  # useManagedIdentity: false
  # accountKey: "<your-storage-key>"
```

### Step 6: Troubleshooting BlobFuse

```bash
# Check if BlobFuse mount is successful
kubectl logs -f -n ${TENSORBOARD_NAMESPACE} <pod-name>

# Verify mount inside pod
kubectl exec -it -n ${TENSORBOARD_NAMESPACE} <pod-name> -- mount | grep /logs

# Check TensorBoard logs directory
kubectl exec -it -n ${TENSORBOARD_NAMESPACE} <pod-name> -- find /logs -type f | head -20
```

---

## Complete Installation Script

For a fully automated installation of all components:

```bash
#!/bin/bash
set -e

echo "🚀 Starting Infrastructure Installation..."

# ============ ENVIRONMENT SETUP ============
export SUBSCRIPTION_ID="<your-subscription-id>"
export RESOURCE_GROUP="<your-resource-group>"
export AKS_CLUSTER_NAME="<your-aks-cluster>"
export LOCATION="<your-location>"

az login
az account set --subscription ${SUBSCRIPTION_ID}
az configure --defaults group=${RESOURCE_GROUP} location=${LOCATION}

az aks get-credentials \
  --resource-group ${RESOURCE_GROUP} \
  --name ${AKS_CLUSTER_NAME} \
  --overwrite-existing

# ============ POSTGRESQL ============
echo "📦 Installing PostgreSQL..."
export POSTGRES_NAMESPACE="postgres"
export POSTGRES_DB="appdb"
export POSTGRES_USER="appuser"
export POSTGRES_PASSWORD="$(openssl rand -base64 32)"

kubectl create namespace ${POSTGRES_NAMESPACE}
kubectl create secret generic postgres-akv-secret \
  --from-literal=POSTGRES_DB=${POSTGRES_DB} \
  --from-literal=POSTGRES_USER=${POSTGRES_USER} \
  --from-literal=POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  -n ${POSTGRES_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

helm install postgres ./charts/postgres \
  --namespace ${POSTGRES_NAMESPACE} \
  --values ./charts/postgres/values.yaml

kubectl rollout status statefulset/postgres-postgres -n ${POSTGRES_NAMESPACE}
echo "✅ PostgreSQL installed"

# ============ REDIS ============
echo "📦 Installing Redis..."
export REDIS_NAMESPACE="redis"

kubectl create namespace ${REDIS_NAMESPACE}

helm install redis ./charts/redis \
  --namespace ${REDIS_NAMESPACE} \
  --values ./charts/redis/values.yaml

kubectl rollout status deployment/redis-redis -n ${REDIS_NAMESPACE}
echo "✅ Redis installed"

# ============ KAFKA ============
echo "📦 Installing Kafka..."
export KAFKA_NAMESPACE="kafka"
export KAFKA_CLUSTER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

kubectl create namespace ${KAFKA_NAMESPACE}
kubectl create secret generic kafka-secret \
  --from-literal=KAFKA_CLUSTER_ID=${KAFKA_CLUSTER_ID} \
  -n ${KAFKA_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

helm install kafka ./charts/kafka \
  --namespace ${KAFKA_NAMESPACE} \
  --values ./charts/kafka/values.yaml

kubectl rollout status statefulset/kafka-kafka -n ${KAFKA_NAMESPACE}
echo "✅ Kafka installed"

# ============ KAFKA UI ============
echo "📦 Installing Kafka UI..."
export KAFKAUI_NAMESPACE="kafka-ui"
export KAFKA_BOOTSTRAP_SERVERS="kafka-kafka.${KAFKA_NAMESPACE}.svc.cluster.local:9092"

kubectl create namespace ${KAFKAUI_NAMESPACE}

helm install kafka-ui ./charts/kafka-ui \
  --namespace ${KAFKAUI_NAMESPACE} \
  --set kafka.bootstrapServers=${KAFKA_BOOTSTRAP_SERVERS} \
  --values ./charts/kafka-ui/values.yaml

kubectl rollout status deployment/kafka-ui -n ${KAFKAUI_NAMESPACE}
echo "✅ Kafka UI installed"

# ============ OBSERVABILITY ============
echo "📦 Installing Observability Stack..."
export OBSERVABILITY_NAMESPACE="observability"

kubectl create namespace ${OBSERVABILITY_NAMESPACE}

helm install observability ./charts/observability \
  --namespace ${OBSERVABILITY_NAMESPACE} \
  --values ./charts/observability/values.yaml

kubectl rollout status deployment/jaeger -n ${OBSERVABILITY_NAMESPACE}
echo "✅ Observability stack installed"

# ============ PROMETHEUS STACK ============
echo "📦 Installing Kube Prometheus Stack..."
export MONITORING_NAMESPACE="monitoring"
export GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 32)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace ${MONITORING_NAMESPACE}
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=${GRAFANA_ADMIN_PASSWORD} \
  -n ${MONITORING_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

helm install kube-prometheus-stack ./charts/kube-prometheus-stack \
  --namespace ${MONITORING_NAMESPACE} \
  --values ./charts/kube-prometheus-stack/values.yaml \
  --dependency-update

kubectl rollout status deployment/kube-prometheus-stack-prometheus -n ${MONITORING_NAMESPACE}
echo "✅ Prometheus stack installed"

# ============ MLFLOW ============
echo "📦 Installing MLflow..."
export MLFLOW_NAMESPACE="mlflow"

kubectl create namespace ${MLFLOW_NAMESPACE}
kubectl create secret generic mlflow-db-secret \
  --from-literal=POSTGRES_USER=${POSTGRES_USER} \
  --from-literal=POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  -n ${MLFLOW_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

helm install mlflow ./charts/mlflow \
  --namespace ${MLFLOW_NAMESPACE} \
  --set postgres.host=postgres-postgres.${POSTGRES_NAMESPACE}.svc.cluster.local \
  --set postgres.namespace=${POSTGRES_NAMESPACE} \
  --values ./charts/mlflow/values.yaml

kubectl rollout status deployment/mlflow -n ${MLFLOW_NAMESPACE}
echo "✅ MLflow installed"

# ============ TENSORBOARD ============
echo "📦 Installing TensorBoard..."
export TENSORBOARD_NAMESPACE="mlops"

kubectl create namespace ${TENSORBOARD_NAMESPACE}

helm install tensorboard ./charts/tensorboard \
  --namespace ${TENSORBOARD_NAMESPACE} \
  --set blobStorage.accountName=thinklabsmlflow \
  --set blobStorage.containerName=mlflow-artifacts \
  --values ./charts/tensorboard/values.yaml

kubectl rollout status deployment/tensorboard -n ${TENSORBOARD_NAMESPACE}
echo "✅ TensorBoard installed"

# ============ SUMMARY ============
echo ""
echo "✅ Infrastructure installation complete!"
echo ""
echo "📊 Installed Components:"
echo "  1. PostgreSQL (namespace: ${POSTGRES_NAMESPACE})"
echo "  2. Redis (namespace: ${REDIS_NAMESPACE})"
echo "  3. Kafka (namespace: ${KAFKA_NAMESPACE})"
echo "  4. Kafka UI (namespace: ${KAFKAUI_NAMESPACE})"
echo "  5. Observability - Jaeger & OTEL (namespace: ${OBSERVABILITY_NAMESPACE})"
echo "  6. Prometheus + Grafana (namespace: ${MONITORING_NAMESPACE})"
echo "  7. MLflow (namespace: ${MLFLOW_NAMESPACE})"
echo "  8. TensorBoard (namespace: ${TENSORBOARD_NAMESPACE})"
echo ""
echo "🔐 Saved Credentials:"
echo "  - PostgreSQL: postgres-credentials.txt"
echo "  - Grafana: grafana-credentials.txt"
echo ""
echo "📚 Next Steps:"
echo "  1. Verify all deployments: kubectl get all --all-namespaces"
echo "  2. Access services via port-forward (see commands above)"
echo "  3. Configure ingress for external access (optional)"
echo "  4. Set up monitoring alerts in Grafana"
```

Save this script as `install-infrastructure.sh`, make it executable, and run:

```bash
chmod +x install-infrastructure.sh
./install-infrastructure.sh
```

---

## Troubleshooting

### 1. ImagePullBackOff Error

**Cause:** Missing or incorrect ACR credentials

```bash
# Check imagePullSecrets in pod
kubectl get pods -n <namespace> <pod-name> -o yaml | grep imagePullSecrets

# Create ACR secret if missing
kubectl create secret docker-registry acr-creds \
  --docker-server=thinklabsinternalacrdev.azurecr.io \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n <namespace>

# Restart deployment
kubectl rollout restart deployment/<name> -n <namespace>
```

### 2. PVC Pending

**Cause:** Storage class unavailable

```bash
# Check storage classes
kubectl get storageclass

# Describe PVC for details
kubectl describe pvc <pvc-name> -n <namespace>

# Enable CSI storage drivers if needed
az aks update --enable-azure-csi-storage-drivers \
  -g ${RESOURCE_GROUP} \
  -n ${AKS_CLUSTER_NAME}
```

### 3. Pod CrashLoopBackOff

**Cause:** Application configuration or startup error

```bash
# Check logs
kubectl logs -f -n <namespace> <pod-name>

# Describe pod
kubectl describe pod <pod-name> -n <namespace>

# Check resource limits
kubectl top nodes
kubectl top pods -n <namespace>
```

### 4. Service Discovery Issues

**Cause:** Incorrect DNS names

```bash
# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup <service-name>.<namespace>.svc.cluster.local

# Correct format: <service-name>.<namespace>.svc.cluster.local
```

### 5. Connection Refused

**Cause:** Service not ready or port mismatch

```bash
# Check service endpoints
kubectl get endpoints -n <namespace>

# Check service ports
kubectl get svc -n <namespace> <service-name> -o yaml

# Verify pod is running
kubectl get pods -n <namespace> -o wide
```

---

## 📋 Verification Checklist

After installation, verify all components:

```bash
# Check all namespaces
kubectl get namespaces

# Check all pods
kubectl get pods --all-namespaces

# Check all services
kubectl get svc --all-namespaces

# Check all PVCs
kubectl get pvc --all-namespaces

# Check helm releases
helm list --all-namespaces

# Verify PostgreSQL
kubectl exec -it -n postgres postgres-postgres-0 -- psql -U appuser -d appdb -c "SELECT version();"

# Verify Redis
kubectl run redis-cli --image=redis:7.2 --rm -it --restart=Never -n redis -- redis-cli -h redis ping

# Verify Kafka
kubectl run kafka-test --image=thinklabsinternalacrdev.azurecr.io/infra/kafka/kafka:4.2.0 \
  --rm -it --restart=Never -n kafka -- kafka-broker-api-versions.sh --bootstrap-server kafka-kafka:9092

# Verify Jaeger
kubectl port-forward -n observability svc/jaeger 16686:16686
# Visit: http://localhost:16686

# Verify Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit: http://localhost:9090

# Verify Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Visit: http://localhost:3000
```

---

## 📚 Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Azure AKS Documentation](https://learn.microsoft.com/en-us/azure/aks/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [MLflow Documentation](https://mlflow.org/docs/)
- [TensorBoard Documentation](https://www.tensorflow.org/tensorboard)

---

**Last Updated:** March 2026

For questions or issues, please contact the platform engineering team.

