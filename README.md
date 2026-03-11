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

**Last Updated:** February 2026

For questions or issues, please contact the platform engineering team.

