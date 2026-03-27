# 🚀 Installation Guide: Installing Document Generator Service on AKS using Helm

This guide provides step-by-step instructions to deploy the ThinkLabs Document Generator Service on Azure Kubernetes Service (AKS) using Helm charts.

---

## 📋 Prerequisites

Before starting, ensure you have the following tools installed and configured:

### Required Tools
- **Azure CLI** (`az`) - [Install Guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- **kubectl** - [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm 3** - [Install Guide](https://helm.sh/docs/intro/install/)

### Required Azure Resources (in your environment)
- ✅ AKS Cluster (running and accessible)
- ✅ Resource Group (where your AKS cluster resides)
- ✅ Storage Account (for storing output reports)
- ✅ Managed Identity (linked to your AKS cluster for Workload Identity)

### Required Information from Your Azure Environment
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
export NAMESPACE="<your-namespace>"  # e.g., document-generator-service
export SERVICE_ACCOUNT_NAME="<your-service-account-name>"  # e.g., document-generator-service-sa

# Your Managed Identity details
export MANAGED_IDENTITY_NAME="<your-managed-identity-name>"
export MANAGED_IDENTITY_CLIENT_ID="<your-managed-identity-client-id>"
```

---

## 🔧 Setup Instructions

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

## 🔑 Create ACR Credentials Secret (Required)

The application pulls images from a private ACR registry. You need to create a Kubernetes secret with your ACR credentials.

### Step 4: Set ACR Credentials as Environment Variables

Before creating the secret, export your ACR credentials:

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

# View the secret details (base64 encoded)
kubectl get secret acr-creds -n ${NAMESPACE} -o yaml
```

### Step 7: Test ACR Access (Optional)

To verify the credentials work, you can test pulling an image:

```bash
# Create a test pod that uses the acr-creds secret
kubectl run test-image-pull \
  --image=${ACR_LOGIN_SERVER}/test-image:latest \
  --image-pull-policy=Always \
  --restart=Never \
  --overrides='{"spec": {"imagePullSecrets": [{"name": "acr-creds"}]}}' \
  -n ${NAMESPACE}

# Check the pod status (it will fail if image doesn't exist, but won't fail on auth)
kubectl describe pod test-image-pull -n ${NAMESPACE}

# Clean up the test pod
kubectl delete pod test-image-pull -n ${NAMESPACE}
```

## 🏗️ Infrastructure Setup (One-time)

### Verify Storage Account

Verify that your storage account exists:

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

### Create a Container in Storage Account (if needed)

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

### Managed Identity and RBAC (One-time)

If the Managed Identity is not already set up, create it with the following commands:

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

### Assign Storage Account Access (One-time)

Grant the Managed Identity access to the Storage Account:

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

### Create Workload Identity Federation (One-time)

Set up federated credentials to link the Kubernetes service account to the Managed Identity:

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

# Verify
az identity federated-credential list \
  --identity-name ${MANAGED_IDENTITY_NAME} \
  --resource-group ${RESOURCE_GROUP}
```

---

## 🐳 Image Information

The Docker image is hosted on ThinkLabs Public ACR and is ready to use. You do not need to build or push the image.

**Image Details:**
- **Registry:** `thinklabspublicacr.azurecr.io`
- **Repository:** `thinklabs-document-generator-service-x86`
- **Tag:** `latest` (or specify a version tag)

The Helm chart will automatically pull the image from the public registry during deployment.

---

## 📦 Helm Installation

### Prerequisites for Helm Installation

Before installing the Helm chart, ensure:
1. ✅ Namespace has been created
2. ✅ **`acr-creds` secret has been created** (see steps 4-7 above)
3. ✅ Managed Identity has been set up with Workload Identity Federation
4. ✅ Storage account and container exist
5. ✅ values.yaml has been updated with your environment details

### Step 8: Update values.yaml

Update the `values.yaml` file with your environment-specific values:

```yaml
namespace: <your-namespace>
image:
  repository: <your-acr-login-server>/thinklabs-document-generator-service-x86
  tag: latest
azure:
  storageAccount: <your-storage-account-name>
  container: <your-container-name>
serviceAccount:
  annotations:
    azure.workload.identity/client-id: <your-managed-identity-client-id>
imagePullSecrets:
  - name: acr-creds  # This secret MUST exist before installing
```

### Step 9: Install the Helm Chart

```bash
# Install the helm chart with your values
helm install document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE} \
  --set image.repository=${ACR_LOGIN_SERVER}/thinklabs-document-generator-service-x86 \
  --set azure.storageAccount=${STORAGE_ACCOUNT_NAME} \
  --set azure.container=${STORAGE_CONTAINER} \
  --set "serviceAccount.annotations.azure\.workload\.identity/client-id"=${MANAGED_IDENTITY_CLIENT_ID}
```

**Or with all values from values.yaml:**

```bash
# First, ensure values.yaml is updated as shown above
# Then install the chart
helm install document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE}
```

### Step 10: Verify Deployment

```bash
# Check Helm release
helm list --namespace ${NAMESPACE}

# Check deployment status
kubectl get deployment -n ${NAMESPACE}

# Check pods
kubectl get pods -n ${NAMESPACE}

# Check service account
kubectl get serviceaccount -n ${NAMESPACE}

# Check if acr-creds secret exists
kubectl get secret acr-creds -n ${NAMESPACE}

# View detailed pod information
kubectl describe pod -n ${NAMESPACE} <pod-name>

# Check logs
kubectl logs -n ${NAMESPACE} -l app=document-generator-service
```

### Step 11: Configure Ingress (Optional)

The Helm chart includes an optional Ingress resource for exposing the Document Generator Service via Azure Application Gateway. Ingress is disabled by default and can be enabled during installation.

#### Ingress Configuration Values

The following ingress parameters can be customized in `values.yaml` or via Helm command-line flags:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `ingress.enabled` | Enable/disable the ingress resource | `false` | No |
| `ingress.host` | Host domain for the ingress | `document-generator-service.api.dev.thinklabs.ai` | Yes (when enabled) |
| `ingress.sslCertificate` | Azure AppGW SSL certificate name | `cert-document-generator-service-api-dev-thinklabs-ai-tls` | Yes (when enabled) |
| `ingress.certManagerIssuer` | Cert-manager cluster issuer name | `thinklabs-http` | No |
| `ingress.healthProbePath` | Health check endpoint for Azure AppGW | `/document-generator-service/v1/health` | No |
| `ingress.ingressClassName` | Ingress controller class name | `azure-application-gateway` | No |
| `ingress.pathPrefix` | API path prefix for routing | `/document-generator-service/v1` | No |
| `ingress.annotations` | Additional custom annotations | `{}` | No |

#### Enable Ingress During Installation

**Option 1: Using command-line flags**

```bash
helm install document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE} \
  --set ingress.enabled=true \
  --set ingress.host="document-generator-service.your-domain.com" \
  --set ingress.sslCertificate="your-certificate-name" \
  --set ingress.certManagerIssuer="your-issuer-name" \
  --set ingress.healthProbePath="/health" \
  --set ingress.pathPrefix="/api/v1"
```

**Option 2: Update values.yaml and install**

```yaml
# In values.yaml, update the ingress section:
ingress:
  enabled: true
  host: "document-generator-service.your-domain.com"
  sslCertificate: "your-certificate-name"
  certManagerIssuer: "your-issuer-name"
  healthProbePath: "/document-generator-service/v1/health"
  ingressClassName: "azure-application-gateway"
  pathPrefix: "/document-generator-service/v1"
  annotations: {}
```

Then install:

```bash
helm install document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE}
```

#### Verify Ingress Deployment

```bash
# Check if ingress resource was created
kubectl get ingress -n ${NAMESPACE}

# Describe the ingress
kubectl describe ingress -n ${NAMESPACE} <ingress-name>

# View ingress details in YAML
kubectl get ingress -n ${NAMESPACE} <ingress-name> -o yaml

# Check ingress events
kubectl get events -n ${NAMESPACE} --field-selector involvedObject.kind=Ingress
```

#### Ingress Template Details

The ingress resource is defined in `templates/ingress.yaml` and includes:

- **Metadata:** Ingress name and namespace configuration
- **Annotations:** 
  - `cert-manager.io/cluster-issuer` - Automatic SSL certificate provisioning
  - `appgw.ingress.kubernetes.io/health-probe-path` - Azure AppGW health check
  - `appgw.ingress.kubernetes.io/appgw-ssl-certificate` - SSL certificate binding
- **Spec:**
  - `ingressClassName` - Azure Application Gateway controller
  - `rules` - Host and path-based routing to the Document Generator Service
  - `backend` - Routes requests to the service on the configured port (default: 9999)

#### Example Ingress Configuration

Here's an example of what the generated Ingress resource looks like:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: document-generator-service-ingress
  namespace: document-generator-service
  annotations:
    cert-manager.io/cluster-issuer: "thinklabs-http"
    appgw.ingress.kubernetes.io/health-probe-path: "/document-generator-service/v1/health"
    appgw.ingress.kubernetes.io/appgw-ssl-certificate: "cert-document-generator-service-api-dev-thinklabs-ai-tls"
spec:
  ingressClassName: azure-application-gateway
  rules:
    - host: api.dev.thinklabs.ai
      http:
        paths:
          - path: /document-generator-service/v1
            pathType: Prefix
            backend:
              service:
                name: document-generator-service
                port:
                  number: 9999
```

#### Upgrade Ingress Configuration

To update ingress settings after deployment:

```bash
# Upgrade with new ingress parameters
helm upgrade document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE} \
  --set ingress.enabled=true \
  --set ingress.host="new-host.your-domain.com"

# Or disable ingress
helm upgrade document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE} \
  --set ingress.enabled=false
```

#### Ingress Prerequisites

Before enabling ingress, ensure:
- ✅ Azure Application Gateway Ingress Controller is installed on your AKS cluster
- ✅ Cert-manager is installed and configured (if using automatic SSL provisioning)
- ✅ The domain name is registered and DNS is configured
- ✅ SSL certificate exists in Azure AppGW (if not using cert-manager for auto-provisioning)
- ✅ Appropriate ingress controller role assignments are in place

---

## 🔍 Troubleshooting

### Check Image Pull Issues

```bash
# Describe the pod to see events
kubectl describe pod -n ${NAMESPACE} <pod-name>

# Check if image is being pulled
kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'
```

### Check Workload Identity

```bash
# Verify service account has the correct annotation
kubectl get serviceaccount -n ${NAMESPACE} \
  <your-service-account-name> -o yaml

# Check pod identity binding
kubectl describe pod -n ${NAMESPACE} <pod-name> | grep azure.workload.identity
```

### Test Azure Connectivity

```bash
# Execute into the pod
kubectl exec -it -n ${NAMESPACE} <pod-name> -- /bin/bash

# Inside the pod, test Azure access
python -c "from azure.identity import DefaultAzureCredential; print(DefaultAzureCredential().get_token('https://storage.azure.com'))"
```

### View Application Logs

```bash
# Stream logs
kubectl logs -f -n ${NAMESPACE} -l app=document-generator-service

# View logs from a specific pod
kubectl logs -n ${NAMESPACE} <pod-name>
```

---

## 🔄 Helm Operations

### Upgrade the Release

```bash
# Upgrade with new image tag
helm upgrade document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE} \
  --set image.tag=<new-tag>
```

### Uninstall the Release

```bash
# Remove the Helm release
helm uninstall document-generator-service \
  --namespace ${NAMESPACE}
```

**Note:** This removes the deployment but keeps the namespace and secrets. To delete the namespace as well:

```bash
kubectl delete namespace ${NAMESPACE}
```

---

## 📝 Environment Variables Summary

The application uses the following environment variables (set via Helm values):

| Variable | Value | Source |
|----------|-------|--------|
| `STORAGE_TYPE` | `azure` | `values.yaml` |
| `AZURE_STORAGE_CONTAINER` | `reports` | `values.yaml` |
| `AZURE_PROTOCOL` | `az` | `values.yaml` |
| `AZURE_STORAGE_ACCOUNT` | `thinklabsdocgen` | `values.yaml` |
| `AZURE_TENANT_ID` | Auto-detected | Workload Identity |
| `AZURE_CLIENT_ID` | `<MANAGED_IDENTITY_CLIENT_ID>` | Service Account Annotation |

---

## 🔐 Security Best Practices

1. **Never commit secrets to the repository**
   - ACR credentials are created as a secret in the cluster
   - Managed Identity handles Azure authentication without storing keys

2. **Use Workload Identity Federation**
   - Eliminates the need for service principal keys
   - Provides time-limited tokens automatically

3. **Least Privilege Access**
   - Managed Identity has only `Storage Blob Data Contributor` and `AcrPull` roles
   - No full storage account access keys required

4. **Network Security**
   - Consider using Azure Private Endpoints for storage account
   - Restrict ACR access to AKS cluster network

---

## 📚 Additional Resources

- [Azure Workload Identity Documentation](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Helm Documentation](https://helm.sh/docs/)
- [AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [Azure Storage Firewall and Virtual Networks](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security)

---

## ❓ FAQ

**Q: Why do I need to create the acr-creds secret?**
A: The `acr-creds` secret provides Docker authentication credentials for pulling the container image from the private ACR registry. Without it, Kubernetes cannot pull the image and the pod will fail to start.

**Q: What if I forget to create the acr-creds secret?**
A: The pod will fail with an `ImagePullBackOff` error. You can create the secret later and redeploy the pod. See the troubleshooting section for details.

**Q: Can I use a different secret name?**
A: Yes, but you must update the `imagePullSecrets.name` in values.yaml to match the secret you created.


**Q: Can I use service principal keys instead of Workload Identity?**
A: Yes, but Workload Identity is more secure and is the recommended approach for AKS.

**Q: What happens if the Docker image pull fails?**
A: The pod will fail to start. Check that:
   - The `acr-creds` secret exists and is correct
   - The image URL is correct
   - The image exists in your ACR registry
   - The ACR credentials have permission to pull the image

**Q: How do I update the application?**
A: Build a new image with a new tag and push to your ACR, then upgrade the Helm release with the new tag:
```bash
helm upgrade document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE} \
  --set image.tag=<new-tag>
```

---

---

# 🗂️ Complete Chart Installation Guide

This section provides installation instructions for all charts in this repository.

## 📊 Chart Overview

| Chart | Purpose | Version | Dependencies |
|-------|---------|---------|--------------|
| **document-generator-service** | Document generation microservice | 0.1.0 | None |
| **kafka** | Apache Kafka single broker (KRaft mode) | 0.1.0 | None |
| **kafka-ui** | Kafka Web UI Dashboard | 0.1.0 | Kafka |
| **postgres** | PostgreSQL Database | 0.1.0 | None |
| **redis** | Redis In-Memory Cache | 0.1.0 | None |
| **observability** | Jaeger + OpenTelemetry Collector | 0.1.0 | None |
| **kube-prometheus-stack** | Prometheus + Grafana + Alertmanager | 0.1.0 | Prometheus Community Charts |
| **mlflow** | MLflow Model Tracking (Placeholder) | 0.1.0 | None |

---

## 🚀 Installation Order & Dependencies

**Recommended installation order:**

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
8. mlflow (optional - ML tracking)
```

---

## 🗄️ PostgreSQL Installation

PostgreSQL serves as the primary database for the platform.

### Prerequisites

- AKS cluster with `managed-csi-premium` storage class
- Namespace created (recommended: `postgres`)
- Node pool with label `workload: postgres` (or modify nodeSelector)

### Installation Steps

```bash
# Set environment variables
export POSTGRES_NAMESPACE="postgres"
export POSTGRES_PASSWORD="your-secure-password-here"
export POSTGRES_DB="appdb"
export POSTGRES_USER="appuser"

# Create namespace
kubectl create namespace ${POSTGRES_NAMESPACE}

# Install PostgreSQL chart
helm install postgres ./charts/postgres \
  --namespace ${POSTGRES_NAMESPACE} \
  --set postgres.password=${POSTGRES_PASSWORD} \
  --set postgres.database=${POSTGRES_DB} \
  --set postgres.username=${POSTGRES_USER} \
  --set persistence.size=128Gi \
  --set service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-internal"="true"
```

### Verify Installation

```bash
# Check deployment status
kubectl get deployment -n ${POSTGRES_NAMESPACE}
kubectl get pvc -n ${POSTGRES_NAMESPACE}

# Check pod logs
kubectl logs -f -n ${POSTGRES_NAMESPACE} -l app=postgres

# Get database connection details
POSTGRES_HOST=$(kubectl get svc -n ${POSTGRES_NAMESPACE} postgres -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "PostgreSQL Host: $POSTGRES_HOST"
echo "PostgreSQL Port: 5432"
echo "Database: ${POSTGRES_DB}"
echo "Username: ${POSTGRES_USER}"
```

### Update Values

Key configuration parameters in `values.yaml`:

```yaml
postgres:
  database: appdb
  username: appuser
  password: "change-me"  # CHANGE THIS!
  existingSecret: ""     # Optional: use existing secret

persistence:
  size: 128Gi            # Adjust storage size
  storageClass: managed-csi-premium

service:
  type: LoadBalancer     # Or ClusterIP for internal only
  port: 5432

nodeSelector:
  workload: postgres     # Ensure nodes have this label
```

---

## 🔴 Redis Installation

Redis provides in-memory caching for the platform.

### Prerequisites

- AKS cluster with `managed-csi` storage class
- Namespace created (recommended: `redis`)
- Node pool with label `workload-type: general`

### Installation Steps

```bash
# Set environment variables
export REDIS_NAMESPACE="redis"

# Create namespace (chart can auto-create)
kubectl create namespace ${REDIS_NAMESPACE}

# Install Redis chart
helm install redis ./charts/redis \
  --namespace ${REDIS_NAMESPACE} \
  --set namespace.create=true \
  --set namespace.name=${REDIS_NAMESPACE} \
  --set redis.persistence.size=5Gi \
  --set redis.persistence.storageClassName=managed-csi
```

### Verify Installation

```bash
# Check deployment
kubectl get deployment -n ${REDIS_NAMESPACE}
kubectl get pvc -n ${REDIS_NAMESPACE}

# Get Redis connection details
REDIS_HOST=$(kubectl get svc -n ${REDIS_NAMESPACE} redis -o jsonpath='{.spec.clusterIP}')
REDIS_PORT=$(kubectl get svc -n ${REDIS_NAMESPACE} redis -o jsonpath='{.spec.ports[0].port}')

echo "Redis Host: $REDIS_HOST"
echo "Redis Port: $REDIS_PORT"

# Test Redis connection from a pod
kubectl run redis-test --image=redis:7.2 --rm -it --restart=Never \
  -- redis-cli -h $REDIS_HOST -p $REDIS_PORT ping
```

### Update Values

Key configuration parameters:

```yaml
redis:
  enabled: true
  replicaCount: 1
  
  persistence:
    enabled: true
    size: 5Gi
    storageClassName: managed-csi
  
  auth:
    enabled: false        # Enable auth if needed
    password: ""          # Set password if auth enabled
  
  service:
    type: ClusterIP       # Internal-only access
    port: 6379
```

---

## 📨 Apache Kafka Installation

Kafka serves as the message broker for event streaming.

### Prerequisites

- AKS cluster with `managed-csi` storage class
- Namespace created (recommended: `kafka`)
- Node pool with label `workload-type: general`
- Persistent storage available (default: 100Gi)

### Installation Steps

```bash
# Set environment variables
export KAFKA_NAMESPACE="kafka"
export KAFKA_CLUSTER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

# Create namespace
kubectl create namespace ${KAFKA_NAMESPACE}

# Create Kafka secret with cluster ID
kubectl create secret generic kafka-secret \
  --from-literal=KAFKA_CLUSTER_ID=${KAFKA_CLUSTER_ID} \
  -n ${KAFKA_NAMESPACE}

# Install Kafka chart
helm install kafka ./charts/kafka \
  --namespace ${KAFKA_NAMESPACE} \
  --set kraft.clusterId=${KAFKA_CLUSTER_ID} \
  --set persistence.size=100Gi \
  --set persistence.storageClass=managed-csi \
  --set service.port=9092
```

### Verify Installation

```bash
# Check StatefulSet and pods
kubectl get statefulset -n ${KAFKA_NAMESPACE}
kubectl get pods -n ${KAFKA_NAMESPACE}
kubectl get pvc -n ${KAFKA_NAMESPACE}

# Get Kafka broker address
KAFKA_BROKER=$(kubectl get svc -n ${KAFKA_NAMESPACE} kafka -o jsonpath='{.spec.clusterIP}'):9092
echo "Kafka Bootstrap Server: $KAFKA_BROKER"

# Check Kafka logs
kubectl logs -f -n ${KAFKA_NAMESPACE} kafka-0

# Create a test topic
kubectl run kafka-client --image=thinklabsinternalacrdev.azurecr.io/infra/kafka/kafka:4.2.0 \
  --rm -it --restart=Never -n ${KAFKA_NAMESPACE} \
  -- kafka-topics.sh --create --topic test --bootstrap-server kafka:9092 --partitions 1 --replication-factor 1
```

### Update Values

Key configuration parameters:

```yaml
kraft:
  clusterId: ""           # Auto-generated or set manually

service:
  port: 9092             # Client port
  headlessPort: 9092     # Headless service port

persistence:
  size: 100Gi            # Adjust based on needs
  storageClass: managed-csi

resources:
  requests:
    cpu: "1"
    memory: "2Gi"
  limits:
    cpu: "2"
    memory: "4Gi"

listeners:
  client:
    port: 9092
  controller:
    port: 9093
  interBroker:
    port: 9094
```

---

## 📊 Kafka UI Installation

Kafka UI provides a web interface for Kafka management and monitoring.

### Prerequisites

- Kafka chart already installed and running
- Namespace created (recommended: `kafka-ui`)
- Node pool with label `workload-type: general`

### Installation Steps

```bash
# Set environment variables
export KAFKAUI_NAMESPACE="kafka-ui"
export KAFKA_NAMESPACE="kafka"

# Create namespace
kubectl create namespace ${KAFKAUI_NAMESPACE}

# Get Kafka bootstrap servers
export KAFKA_BOOTSTRAP_SERVERS="kafka-kafka.${KAFKA_NAMESPACE}.svc.cluster.local:9092"

# Install Kafka UI chart
helm install kafka-ui ./charts/kafka-ui \
  --namespace ${KAFKAUI_NAMESPACE} \
  --set kafka.bootstrapServers=${KAFKA_BOOTSTRAP_SERVERS} \
  --set kafka.clusterName="thinklabs-dev-kafka" \
  --set ingress.enabled=false
```

### Enable Ingress (Optional)

To expose Kafka UI via ingress with OAuth:

```bash
helm upgrade kafka-ui ./charts/kafka-ui \
  --namespace ${KAFKAUI_NAMESPACE} \
  --set ingress.enabled=true \
  --set ingress.host="kafka-ui.your-domain.com" \
  --set ingress.className="nginx" \
  --set ingress.tls.enabled=true \
  --set ingress.tls.secretName="kafka-ui-tls"
```

### Verify Installation

```bash
# Check deployment
kubectl get deployment -n ${KAFKAUI_NAMESPACE}

# Port-forward to access UI locally
kubectl port-forward -n ${KAFKAUI_NAMESPACE} svc/kafka-ui 8080:8080

# Access at: http://localhost:8080
```

### Update Values

Key configuration parameters:

```yaml
kafka:
  bootstrapServers: "kafka-kafka.kafka.svc.cluster.local:9092"
  clusterName: "thinklabs-dev-kafka"

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: false
  className: nginx
  host: kafka-ui.dev.thinklabs.ai
  path: /
  pathType: Prefix
  tls:
    enabled: false
    secretName: ""
  annotations:
    nginx.ingress.kubernetes.io/auth-url: "https://auth.dev.thinklabs.ai/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://auth.dev.thinklabs.ai/oauth2/start?rd=$scheme://$http_host$escaped_request_uri"
```

---

## 🔍 Observability Stack Installation

The observability stack includes Jaeger (distributed tracing) and OpenTelemetry Collector.

### Prerequisites

- AKS cluster with persistent storage
- Namespace created (recommended: `observability`)
- Node pool with label `workload-type: general`

### Installation Steps

```bash
# Set environment variables
export OBSERVABILITY_NAMESPACE="observability"

# Create namespace
kubectl create namespace ${OBSERVABILITY_NAMESPACE}

# Install observability chart
helm install observability ./charts/observability \
  --namespace ${OBSERVABILITY_NAMESPACE} \
  --set namespace.create=false \
  --set namespace.name=${OBSERVABILITY_NAMESPACE} \
  --set jaeger.enabled=true \
  --set otelCollector.enabled=true
```

### Verify Installation

```bash
# Check deployments
kubectl get deployment -n ${OBSERVABILITY_NAMESPACE}
kubectl get pods -n ${OBSERVABILITY_NAMESPACE}

# Access Jaeger UI via port-forward
kubectl port-forward -n ${OBSERVABILITY_NAMESPACE} svc/jaeger 16686:16686

# Access Jaeger UI at: http://localhost:16686

# Check Jaeger logs
kubectl logs -f -n ${OBSERVABILITY_NAMESPACE} -l app=jaeger

# Check OTEL Collector logs
kubectl logs -f -n ${OBSERVABILITY_NAMESPACE} -l app=otel-collector
```

### Configuration

The OTEL Collector is configured to:
- Receive telemetry via OTLP gRPC on port 4317
- Receive telemetry via OTLP HTTP on port 4318
- Export traces to Jaeger on port 4317

Update the collector config in `values.yaml`:

```yaml
otelCollector:
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch:

    exporters:
      otlp:
        endpoint: jaeger:4317
        tls:
          insecure: true

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlp, logging]
```

### Application Integration

To send traces from your application:

```bash
# Set OTEL exporter endpoint
export OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector.observability.svc.cluster.local:4317"
export OTEL_SERVICE_NAME="your-app-name"
export OTEL_TRACES_EXPORTER="otlp"
```

---

## 📈 Kube Prometheus Stack Installation

Complete monitoring stack with Prometheus, Grafana, and Alertmanager.

### Prerequisites

- AKS cluster with `managed-csi` storage class
- Namespace created (recommended: `monitoring`)
- Node pool with label `workload-type: general`
- Helm repo added: `helm repo add prometheus-community https://prometheus-community.github.io/helm-charts`

### Installation Steps

```bash
# Set environment variables
export MONITORING_NAMESPACE="monitoring"
export GRAFANA_ADMIN_PASSWORD="your-secure-password"

# Create namespace
kubectl create namespace ${MONITORING_NAMESPACE}

# Create Grafana admin secret
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=${GRAFANA_ADMIN_PASSWORD} \
  -n ${MONITORING_NAMESPACE}

# Update Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install kube-prometheus-stack ./charts/kube-prometheus-stack \
  --namespace ${MONITORING_NAMESPACE} \
  --set kube-prometheus-stack.prometheus.prometheusSpec.retention=30d \
  --set kube-prometheus-stack.prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]=ReadWriteOnce \
  --set kube-prometheus-stack.prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi
```

### Verify Installation

```bash
# Check all components
kubectl get all -n ${MONITORING_NAMESPACE}

# Access Prometheus UI
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-prometheus 9090:9090
# Access at: http://localhost:9090

# Access Grafana UI
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-grafana 3000:80
# Access at: http://localhost:3000
# Login with admin / ${GRAFANA_ADMIN_PASSWORD}

# Access Alertmanager UI
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-alertmanager 9093:9093
# Access at: http://localhost:9093

# Check alerting rules
kubectl get prometheusrules -n ${MONITORING_NAMESPACE}
```

### Update Values

Key configuration parameters:

```yaml
kube-prometheus-stack:
  alertmanager:
    enabled: true
    alertmanagerSpec:
      replicas: 1
      storage:
        volumeClaimTemplate:
          spec:
            storageClassName: managed-csi
            accessModes: [ReadWriteOnce]
            resources:
              requests:
                storage: 20Gi

  grafana:
    enabled: true
    persistence:
      enabled: true
      storageClassName: managed-csi
      size: 20Gi
    admin:
      existingSecret: grafana-admin-secret

  prometheus:
    prometheusSpec:
      retention: 30d
      storageSpec:
        volumeClaimTemplate:
          spec:
            storageClassName: managed-csi
            resources:
              requests:
                storage: 50Gi
```

---

## 🎯 Document Generator Service Installation

Complete installation instructions already provided above in this README.

### Quick Install

```bash
export NAMESPACE="document-generator-service"
export ACR_LOGIN_SERVER="your-acr.azurecr.io"
export STORAGE_ACCOUNT_NAME="your-storage-account"
export STORAGE_CONTAINER="reports"
export MANAGED_IDENTITY_CLIENT_ID="your-client-id"

kubectl create namespace ${NAMESPACE}

kubectl create secret docker-registry acr-creds \
  --docker-server=${ACR_LOGIN_SERVER} \
  --docker-username=${ACR_USERNAME} \
  --docker-password=${ACR_PASSWORD} \
  --docker-email=${DOCKER_EMAIL} \
  --namespace=${NAMESPACE}

helm install document-generator-service ./charts/document-generator-service \
  --namespace ${NAMESPACE} \
  --set image.repository=${ACR_LOGIN_SERVER}/thinklabs-document-generator-service-x86 \
  --set azure.storageAccount=${STORAGE_ACCOUNT_NAME} \
  --set azure.container=${STORAGE_CONTAINER} \
  --set "serviceAccount.annotations.azure\.workload\.identity/client-id"=${MANAGED_IDENTITY_CLIENT_ID}
```

---

## 🧪 MLflow Installation (Placeholder)

MLflow serves as the model tracking and management system.

### Current Status

The MLflow chart is currently a placeholder. To properly set up MLflow:

1. **Option A: Use MLflow Helm Chart (Community)**

```bash
helm repo add community-charts https://charts.bitnami.com/bitnami
helm repo update

helm install mlflow community-charts/mlflow \
  --namespace mlflow \
  --create-namespace \
  --set postgresql.auth.password=mlflow-password \
  --set service.type=ClusterIP
```

2. **Option B: Use Thinklabs Custom Chart**

When the MLflow chart is implemented, use:

```bash
kubectl create namespace mlflow

helm install mlflow ./charts/mlflow \
  --namespace mlflow
```

### Verify Installation

```bash
# Check MLflow service
kubectl get svc -n mlflow

# Port-forward to access UI
kubectl port-forward -n mlflow svc/mlflow 5000:5000

# Access MLflow UI at: http://localhost:5000
```

---

## 🔄 Complete Platform Installation Script

For a complete platform setup, use this orchestrated installation:

```bash
#!/bin/bash

set -e

echo "🚀 Starting ThinkLabs Platform Installation..."

# Set variables
export SUBSCRIPTIONS_ID="<your-subscription>"
export RESOURCE_GROUP="<your-rg>"
export AKS_CLUSTER_NAME="<your-cluster>"
export LOCATION="eastus"

# 1. PostgreSQL
echo "📦 Installing PostgreSQL..."
kubectl create namespace postgres || true
helm install postgres ./charts/postgres \
  --namespace postgres \
  --set postgres.password="$(openssl rand -base64 32)"

# 2. Redis
echo "📦 Installing Redis..."
helm install redis ./charts/redis \
  --namespace redis \
  --create-namespace

# 3. Kafka
echo "📦 Installing Kafka..."
kubectl create namespace kafka || true
KAFKA_CLUSTER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
kubectl create secret generic kafka-secret \
  --from-literal=KAFKA_CLUSTER_ID=${KAFKA_CLUSTER_ID} \
  -n kafka --dry-run=client -o yaml | kubectl apply -f -

helm install kafka ./charts/kafka \
  --namespace kafka \
  --set kraft.clusterId=${KAFKA_CLUSTER_ID}

# 4. Kafka UI
echo "📦 Installing Kafka UI..."
helm install kafka-ui ./charts/kafka-ui \
  --namespace kafka-ui \
  --create-namespace \
  --set kafka.bootstrapServers="kafka-kafka.kafka.svc.cluster.local:9092"

# 5. Observability
echo "📦 Installing Observability Stack..."
helm install observability ./charts/observability \
  --namespace observability \
  --create-namespace

# 6. Kube Prometheus Stack
echo "📦 Installing Monitoring Stack..."
kubectl create namespace monitoring || true
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 32)" \
  -n monitoring --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack ./charts/kube-prometheus-stack \
  --namespace monitoring

# 7. Document Generator Service
echo "📦 Installing Document Generator Service..."
kubectl create namespace document-generator-service || true
# Create acr-creds secret before installing

helm install document-generator-service ./charts/document-generator-service \
  --namespace document-generator-service

echo "✅ Platform installation complete!"
echo ""
echo "📊 Installed Components:"
echo "  - PostgreSQL (namespace: postgres)"
echo "  - Redis (namespace: redis)"
echo "  - Kafka (namespace: kafka)"
echo "  - Kafka UI (namespace: kafka-ui)"
echo "  - Observability - Jaeger & OTEL (namespace: observability)"
echo "  - Prometheus + Grafana (namespace: monitoring)"
echo "  - Document Generator Service (namespace: document-generator-service)"
```

---

## 🛠️ Troubleshooting Common Issues

### 1. ImagePullBackOff Error

**Cause:** ACR credentials not set or incorrect image path

```bash
# Check if imagePullSecrets are configured
kubectl get pods -n <namespace> <pod-name> -o yaml | grep imagePullSecrets

# Create or update ACR secret
kubectl create secret docker-registry acr-creds \
  --docker-server=<acr-url> \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n <namespace> --dry-run=client -o yaml | kubectl apply -f -

# Restart pods
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

### 2. PVC Pending

**Cause:** Storage class not available

```bash
# List available storage classes
kubectl get storageclass

# Check PVC status
kubectl describe pvc <pvc-name> -n <namespace>

# Update chart to use available storage class
helm upgrade <release> ./charts/<chart> \
  --namespace <namespace> \
  --set persistence.storageClass=<available-class>
```

### 3. Pod CrashLoopBackOff

**Cause:** Application configuration or resource issues

```bash
# Check logs
kubectl logs -f -n <namespace> <pod-name>

# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Check resource availability
kubectl top nodes
kubectl top pods -n <namespace>
```

### 4. Service Discovery Issues

**Cause:** Incorrect hostname in configuration

```bash
# Verify service DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup <service-name>.<namespace>.svc.cluster.local

# Update values to use correct DNS name
# Format: <service-name>.<namespace>.svc.cluster.local
```

---

## 📋 Pre-Installation Checklist

Before installing all charts, verify:

- ✅ AKS cluster is running and accessible
- ✅ kubectl is configured and authenticated
- ✅ Helm 3.x is installed
- ✅ Enough storage classes available (`managed-csi`, `managed-csi-premium`)
- ✅ Node pools have required labels (`workload-type: general`, `workload: postgres`, etc.)
- ✅ ACR credentials are available
- ✅ Required namespaces can be created
- ✅ Storage accounts and managed identities are set up (for Document Generator Service)
- ✅ Sufficient cluster resources (CPU, memory)

---

## 📚 Additional References

- [Helm Documentation](https://helm.sh/docs/)
- [Apache Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [Jaeger Distributed Tracing](https://www.jaegertracing.io/)
- [OpenTelemetry](https://opentelemetry.io/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

---

**Last Updated:** March 2026

For questions or issues, please contact the platform engineering team.

