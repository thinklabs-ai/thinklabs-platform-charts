# AKS Deployment Guide

This directory contains templates and configurations for deploying the ThinkLabs MLOps Orchestrator to Azure AKS.

## Architecture

- **Kafka**: Deployed in AKS under a dedicated nodepool
- **Redis**: Either in-cluster or Azure Cache for Redis (optional)
- **API & Consumer**: Deployed in application nodepool
- **Container Registry**: Azure Container Registry (ACR)

## Files Overview

- **values-azure-dev.yaml** - Development environment configuration (2 replicas, smaller resources)
- **values-azure-prod.yaml** - Production environment configuration (3 replicas, larger resources)
- **secrets-example.yaml** - Example template for Kubernetes secrets (DO NOT commit with real values)
- **create-secrets.sh** - Interactive script to create optional secrets in your cluster

## Quick Start

### 1. Prerequisites

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

### 2. Configure Helm Values

The values files are already configured for in-cluster Kafka:

```yaml
KAFKA_BROKERS: "kafka-broker-service.kafka:9092"
REDIS_ADDR: "redis-service.redis:6379"  # or Azure managed Redis
```

If you're using **Azure Cache for Redis** instead of in-cluster:
- Edit `values-azure-dev.yaml` or `values-azure-prod.yaml`
- Update `REDIS_ADDR` to your Azure Redis endpoint
- Update `REDIS_TLS_ENABLED` to `"true"`

### 3. Create Namespace and Optional Secrets

```bash
# Create namespace
kubectl create namespace thinklabs-orchestrator

# Create optional secrets (interactive)
chmod +x create-secrets.sh
./create-secrets.sh thinklabs-orchestrator
```

**Optional secrets**:
- Redis credentials (only if using Azure Cache for Redis)
- Slack webhook URL
- ACR pull secrets (if using private registry)

### 4. Install NGINX Ingress Controller (if not present)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

### 5. Deploy with Helm

**Development:**
```bash
helm install thinklabs . \
  -f values-azure-dev.yaml \
  -n thinklabs-orchestrator
```

**Production:**
```bash
helm install thinklabs . \
  -f values-azure-prod.yaml \
  -n thinklabs-orchestrator-prod
```

### 6. Verify Deployment

```bash
# Check pods
kubectl get pods -n thinklabs-orchestrator

# Check services
kubectl get svc -n thinklabs-orchestrator

# Check ingress
kubectl get ingress -n thinklabs-orchestrator

# View logs
kubectl logs -f deployment/orchestrator-api -n thinklabs-orchestrator
```

## Environment-Specific Configurations

### Development (values-azure-dev.yaml)
- 2 replicas for API
- Single replica for status-consumer
- Smaller resource limits (500m CPU, 512Mi memory)
- Domain: `dev.service.thinklabs.ai`
- Kafka in same cluster

### Production (values-azure-prod.yaml)
- 3 replicas for API
- Single replica for status-consumer
- Larger resource limits (1 CPU, 1Gi memory)
- Domain: `service.thinklabs.ai`
- No notifications for PENDING status
- Kafka in same cluster

## Common Commands

### Update Deployment
```bash
helm upgrade thinklabs . \
  -f values-azure-dev.yaml \
  -n thinklabs-orchestrator
```

### Rollback
```bash
helm rollback thinklabs 1 -n thinklabs-orchestrator
```

### Check Values
```bash
helm get values thinklabs -n thinklabs-orchestrator
```

### Dry Run (Recommended before deploy)
```bash
helm install thinklabs . \
  -f values-azure-dev.yaml \
  -n thinklabs-orchestrator \
  --dry-run --debug
```

## Health Checks

The deployments include:
- **Liveness probe**: Checks `/health` endpoint every 10 seconds (API)
- **Readiness probe**: Checks `/health` endpoint every 5 seconds (API)
- Failure threshold: 3 for liveness, 2 for readiness

**Note**: Ensure your API implements the `/health` endpoint.

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n thinklabs-orchestrator
kubectl logs <pod-name> -n thinklabs-orchestrator
```

### Kafka connection issues
```bash
# Check if Kafka is accessible from pods
kubectl exec -it <pod-name> -n thinklabs-orchestrator -- bash
# Inside pod: nc -zv kafka-broker-service.kafka 9092
```

### Check topic creation
```bash
# Verify topics exist
kubectl logs deployment/orchestrator-api -n thinklabs-orchestrator | grep -i topic
```

### Ingress not accessible
```bash
# Check ingress status
kubectl describe ingress orchestrator-api -n thinklabs-orchestrator

# Check cert status (if using cert-manager)
kubectl get certificaterequests -n thinklabs-orchestrator
```

## Image Tagging Strategy

For AKS deployment, use proper version tags:
```bash
# Development builds
docker build -f Dockerfile.orchestrator-api -t thinklabsacr.azurecr.io/orchestrator-api:1.0.0-dev .

# Production releases
docker build -f Dockerfile.orchestrator-api -t thinklabsacr.azurecr.io/orchestrator-api:1.0.0 .
```

Update `values-*.yaml` with specific tags, not `latest`.

## Security Best Practices

1. **Network Policies**: Restrict traffic between pods and namespaces
2. **RBAC**: Use principle of least privilege
3. **TLS**: Always use `https` with proper certificates
4. **Secrets**: Never commit real secrets; use Kubernetes secrets or Azure Key Vault
5. **Image Pull**: Use service principals for ACR authentication
6. **Kafka**: Consider enabling authentication/authorization if not in isolated network

## Optional: Using Azure Cache for Redis

If you prefer managed Redis instead of in-cluster:

### 1. Create Azure Redis Cache
```bash
az redis create \
  --resource-group rg-mlops \
  --name thinklabs-redis \
  --location westus2 \
  --sku Basic
```

### 2. Update values file
```yaml
env:
  REDIS_ADDR: "thinklabs-redis.redis.cache.windows.net:6380"
  REDIS_PASSWORD: ""  # Set via secret
  REDIS_TLS_ENABLED: "true"
```

### 3. Create secret
```bash
REDIS_KEY=$(az redis list-keys --name thinklabs-redis --resource-group rg-mlops --query primaryKey -o tsv)

kubectl create secret generic redis-credentials \
  --from-literal=password="${REDIS_KEY}" \
  -n thinklabs-orchestrator
```

## Migration from Helm Values

If updating existing deployment:
```bash
# Get current values
helm get values thinklabs -n thinklabs-orchestrator > current-values.yaml

# Merge with new values (Kafka broker address might change)
helm upgrade thinklabs . \
  -f values-azure-dev.yaml \
  -n thinklabs-orchestrator
```
