# In-Cluster Kafka Configuration Guide

This document explains the configuration changes made for deploying with Kafka in AKS under a dedicated nodepool.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Azure AKS Cluster                    │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Kafka Nodepool (Dedicated)                      │   │
│  │  - kafka-broker-0, kafka-broker-1, etc.         │   │
│  │  - Service: kafka-broker-service (port 9092)    │   │
│  │  - Namespace: kafka                              │   │
│  └──────────────────────────────────────────────────┘   │
│                          │                                │
│  ┌────────────────────────┼─────────────────────────┐   │
│  │                        ▼                          │   │
│  │  ┌──────────────────────────────────────────┐   │   │
│  │  │  Application Nodepool                    │   │   │
│  │  │  ┌──────────────────────────────────┐   │   │   │
│  │  │  │ orchestrator Namespace│   │   │   │
│  │  │  │ - orchestrator-api (2-3 pods)   │   │   │   │
│  │  │  │ - status-consumer (1 pod)       │   │   │   │
│  │  │  │ - Redis (optional, in-cluster)  │   │   │   │
│  │  │  └──────────────────────────────────┘   │   │   │
│  │  └──────────────────────────────────────────┘   │   │
│  │                                                  │   │
│  │  ┌──────────────────────────────────────────┐   │   │
│  │  │  NGINX Ingress Controller                │   │   │
│  │  │  - Routes traffic to API service         │   │   │
│  │  └──────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────┘   │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

## Key Configuration Changes

### 1. Kafka Connectivity

**Endpoint**: `kafka-broker-service.kafka:9092`
- Service discovery within AKS cluster
- No authentication required (PLAINTEXT protocol)
- Direct pod-to-pod communication

**Environment Variables**:
```yaml
KAFKA_BROKERS: "kafka-broker-service.kafka:9092"
KAFKA_SECURITY_PROTOCOL: "PLAINTEXT"  # No SASL/SSL needed
```

### 2. Topic Naming

Topics follow the pattern: `<tenant>.mlops.<type>`

```yaml
TOPIC_REQUESTS: "thinklabs.mlops.request"
TOPIC_STATUS: "thinklabs.mlops.status"
TOPIC_RESPONSE: "thinklabs.mlops.response"
```

### 3. Redis Configuration

**Default (In-Cluster)**:
```yaml
REDIS_ADDR: "redis-service.redis:6379"
REDIS_TLS_ENABLED: "false"
```

**Optional (Azure Managed)**:
```yaml
REDIS_ADDR: "your-redis.redis.cache.windows.net:6380"
REDIS_TLS_ENABLED: "true"
REDIS_PASSWORD: "via-kubernetes-secret"
```

## Values File Changes

### values-azure-dev.yaml & values-azure-prod.yaml

Previously pointed to:
- Azure Event Hubs for Kafka
- Azure Cache for Redis

Now configured for:
- In-cluster Kafka (kafka namespace)
- In-cluster Redis (redis namespace)
- Optional Azure Redis for production

## Deployment Templates Updated

### deployment-api.yaml & deployment-consumer.yaml

**Changes**:
1. Remove hardcoded SASL authentication
2. Add conditional environment variables for optional Azure Redis
3. Simplify Kafka configuration (no security protocol needed for in-cluster)
4. Add Redis TLS_ENABLED flag

**Removed**:
- `KAFKA_SASL_PASSWORD` secret references (now conditional)
- Azure Event Hubs specific settings

**Added**:
- `KAFKA_SECURITY_PROTOCOL` (conditional)
- `KAFKA_SASL_MECHANISM` (conditional)
- `KAFKA_SASL_USERNAME` (conditional)
- `REDIS_TLS_ENABLED` (conditional)

## Secrets Management

### Minimal Secrets Required

**No Kafka Secrets** - In-cluster Kafka doesn't require authentication

**Optional Secrets**:

1. **Redis (if using Azure Cache)**:
   ```bash
   kubectl create secret generic redis-credentials \
     --from-literal=password='<REDIS_ACCESS_KEY>' \
     -n orchestrator
   ```

2. **Slack (optional)**:
   ```bash
   kubectl create secret generic slack-webhook \
     --from-literal=webhook-url='<SLACK_WEBHOOK_URL>' \
     -n orchestrator
   ```

3. **ACR (if private registry)**:
   ```bash
   kubectl create secret docker-registry acr-secret \
     --docker-server=<ACR_URL> \
     --docker-username=<USERNAME> \
     --docker-password=<PASSWORD> \
     -n orchestrator
   ```

## Helm Chart Files Modified

| File | Changes |
|------|---------|
| `values-azure-dev.yaml` | Updated KAFKA_BROKERS, removed Azure Event Hubs config |
| `values-azure-prod.yaml` | Updated KAFKA_BROKERS, removed Azure Event Hubs config |
| `deployment-api.yaml` | Added conditional env vars, removed required Kafka secret |
| `deployment-consumer.yaml` | Added conditional env vars, removed required Kafka secret |
| `AZURE_DEPLOYMENT.md` | Updated guide for in-cluster Kafka |
| `secrets-example.yaml` | Removed Kafka credentials, made Redis optional |
| `create-secrets.sh` | Made all secrets optional |

## Deployment Steps

### 1. Verify Kafka is Running

```bash
# Check Kafka is ready
kubectl get pods -n kafka
kubectl get svc -n kafka

# Verify bootstraps servers
kubectl get svc kafka-broker-service -n kafka
```

### 2. Configure Values

Values are pre-configured. Only modify if:
- Kafka service name differs
- Using Azure Cache for Redis
- Custom domain/ingress

### 3. Deploy

```bash
# Development
helm install thinklabs . \
  -f values-azure-dev.yaml \
  -n orchestrator \
  --create-namespace

# Production
helm install thinklabs . \
  -f values-azure-prod.yaml \
  -n orchestrator-prod \
  --create-namespace
```

### 4. Verify Topics Created

```bash
# Check topic creation job
kubectl logs jobs/kafka-create-topics -n orchestrator

# Verify topics exist
kubectl exec -it kafka-broker-0 -n kafka -- \
  kafka-topics --bootstrap-server localhost:9092 --list
```

## Troubleshooting

### Kafka Connection Issues

```bash
# Test from pod
kubectl exec -it deployment/orchestrator-api -n orchestrator -- bash
# Inside pod:
nc -zv kafka-broker-service.kafka 9092
```

### Check Configuration

```bash
# View environment variables
kubectl exec -it deployment/orchestrator-api -n orchestrator -- env | grep KAFKA

# Check logs
kubectl logs deployment/orchestrator-api -n orchestrator | grep -i kafka
```

### Topic Creation Failures

```bash
# Check topic creation job
kubectl describe job kafka-create-topics -n orchestrator
kubectl logs jobs/kafka-create-topics -n orchestrator

# Manual topic creation
kubectl exec kafka-broker-0 -n kafka -- \
  kafka-topics --bootstrap-server kafka-broker-service:9092 --create \
  --topic thinklabs.mlops.request --partitions 3 --replication-factor 3
```

## Performance Considerations

### Kafka Deployment
- **Partitions**: 3 (dev), 5 (prod) for parallelism
- **Replication Factor**: 3 for reliability
- **Node Affinity**: Ensure Kafka runs on dedicated nodepool

### API Deployment
- **Replicas**: 2 (dev), 3 (prod)
- **Resource Limits**: 500m CPU / 512Mi memory (dev), 1 CPU / 1Gi (prod)

### Redis (In-Cluster)
- No persistence by default
- Consider StatefulSet for production
- Add persistent volume for data durability

## Migration Path

If migrating from Azure Event Hubs:

1. **Update Helm values**:
   - Kafka endpoint changed
   - Remove SASL settings

2. **Redeploy**:
   ```bash
   helm upgrade thinklabs . -f values-azure-dev.yaml -n orchestrator
   ```

3. **Verify**:
   ```bash
   kubectl logs deployment/orchestrator-api -n orchestrator | grep "KAFKA"
   ```

## Future Options

| Option | Use Case |
|--------|----------|
| In-Cluster Kafka | Dev/Test, PoC |
| Azure Event Hubs | Production, managed service |
| Confluent Cloud | Enterprise, fully managed |
| Self-Managed Kafka | Custom requirements, multi-cluster |

Current setup uses **In-Cluster Kafka** - ideal for AKS deployments with dedicated nodepool resources.
