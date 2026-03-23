# Helm Deployment Guide for Azure AKS

## Pre-Deployment Checklist

### 1. Azure Resources Required
- [ ] Azure Container Registry (ACR) for Docker images
- [ ] Azure Event Hubs or managed Kafka service
- [ ] Azure Cache for Redis
- [ ] Public IP or Ingress controller (NGINX)
- [ ] TLS certificate for ingress domain

### 2. Update Docker Images
```bash
# Build and push images to ACR
az acr build --registry thinklabsacr --image orchestrator-api:latest -f Dockerfile.orchestrator-api .
az acr build --registry thinklabsacr --image status-consumer:latest -f Dockerfile.status-consumer .
```

### 3. Update values-azure-dev.yaml
Replace the following with your actual Azure resources:
- `thinklabsacr.azurecr.io` → Your ACR URL
- `thinklabs-eventhub.servicebus.windows.net` → Your Event Hubs namespace
- `thinklabs-redis.redis.cache.windows.net` → Your Redis Cache name
- `dev.service.thinklabs.ai` → Your ingress domain

### 4. Create Kubernetes Secrets
```bash
# Create secret for Kafka/Event Hubs credentials
kubectl create secret generic kafka-credentials \
  --from-literal=sasl-password='<event-hubs-connection-string>' \
  -n thinklabs-orchestrator

# Create secret for Redis password
kubectl create secret generic redis-credentials \
  --from-literal=password='<redis-access-key>' \
  -n thinklabs-orchestrator

# Create secret for Slack webhook (if used)
kubectl create secret generic slack-webhook \
  --from-literal=webhook-url='<slack-webhook-url>' \
  -n thinklabs-orchestrator
```

### 5. Install NGINX Ingress Controller (if not present)
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

### 6. Deploy the Chart
```bash
# Dry run to verify (recommended)
helm install thinklabs ./charts/thinklabs-orchestrator \
  -f charts/thinklabs-orchestrator/values-azure-dev.yaml \
  -n thinklabs-orchestrator \
  --create-namespace \
  --dry-run --debug

# Actual deployment
helm install thinklabs ./charts/thinklabs-orchestrator \
  -f charts/thinklabs-orchestrator/values-azure-dev.yaml \
  -n thinklabs-orchestrator \
  --create-namespace

# Verify deployment
kubectl get pods -n thinklabs-orchestrator
kubectl get svc -n thinklabs-orchestrator
kubectl get ingress -n thinklabs-orchestrator
```

## Helm Commands for Updates

```bash
# List releases
helm list -n thinklabs-orchestrator

# Get values currently deployed
helm get values thinklabs -n thinklabs-orchestrator

# Upgrade chart
helm upgrade thinklabs ./charts/thinklabs-orchestrator \
  -f charts/thinklabs-orchestrator/values-azure-dev.yaml \
  -n thinklabs-orchestrator

# Rollback if needed
helm rollback thinklabs 1 -n thinklabs-orchestrator
```

## Verification Steps

```bash
# Check pod status
kubectl describe pod <pod-name> -n thinklabs-orchestrator

# View logs
kubectl logs deployment/orchestrator-api -n thinklabs-orchestrator
kubectl logs deployment/status-consumer -n thinklabs-orchestrator

# Check environment variables
kubectl exec -it <pod-name> -n thinklabs-orchestrator -- env | grep -E "KAFKA|REDIS"

# Test API endpoint
kubectl port-forward svc/orchestrator-api 8080:8080 -n thinklabs-orchestrator
# Then access http://localhost:8080
```

## Required Fixes to Templates

The following issues need to be fixed in the deployment templates:

1. **Add resource limits** to deployment-api.yaml and deployment-consumer.yaml
2. **Add health checks** (liveness/readiness probes)
3. **Fix Ingress hostname template** - doesn't support Helm template inside values
4. **Add environment variable references** from Kubernetes secrets
5. **Add image pull secrets** for private ACR access
