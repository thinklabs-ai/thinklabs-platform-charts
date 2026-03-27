# orchestrator-api Helm Chart

MLOps orchestration service Helm chart for Kubernetes deployment with Azure Workload Identity integration.

## Overview

This chart deploys the thinklabs MLOps orchestrator with:
- **orchestrator-api**: Main orchestration API service
- **status-consumer**: Kafka consumer for processing status updates
- **kafka-create-topics**: Initialization job for Kafka topics
- Integration with Redis, Kafka, and OpenTelemetry (OTEL)
- Azure Workload Identity for secure pod authentication
- Slack notifications for workflow status updates

## Quick Start

### Development Deployment

```bash
# 1. Create namespace
kubectl create namespace orchestrator

# 2. Create the local secrets file
cp charts/orchestrator-api/values-dev-secrets.template.yaml charts/orchestrator-api/values-dev-secrets.yaml
# Edit values-dev-secrets.yaml and add your actual Slack webhook URL

# 3. Deploy the chart
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  -f charts/orchestrator-api/values-dev.yaml \
  -f charts/orchestrator-api/values-dev-secrets.yaml
```

### Production Deployment

```bash
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  -f charts/orchestrator-api/values-prod.yaml \
  -f charts/orchestrator-api/values-prod-secrets.yaml
```

## Secrets Management

### **Critical: Never commit secrets to version control**

This chart uses a two-file approach for configuration:

1. **Public values** (`values-*.yaml`):
   - Checked into Git
   - Contains non-sensitive configuration
   - Environment-specific settings (dev, prod, etc.)

2. **Secret values** (`values-*-secrets.yaml`):
   - **Never checked into Git** - see `.gitignore`
   - Contains sensitive credentials (Slack webhook URL)
   - Must be created locally before deployment
   - Use provided `.template.yaml` files as reference

### Setup Instructions

#### For Development

```bash
# 1. Copy the template
cp charts/orchestrator-api/values-dev-secrets.template.yaml \
   charts/orchestrator-api/values-dev-secrets.yaml

# 2. Edit with your Slack webhook URL
vim charts/orchestrator-api/values-dev-secrets.yaml
# Add your actual webhook URL:
# slackWebhook:
#   url: "https://hooks.slack.com/services/T.../B.../..."

# 3. Verify it's in .gitignore (it should be)
grep "values-dev-secrets.yaml" .gitignore
```

#### For Production

```bash
# 1. Copy and customize the template
cp charts/orchestrator-api/values-prod-secrets.template.yaml \
   charts/orchestrator-api/values-prod-secrets.yaml

# 2. Add your production Slack webhook URL
vim charts/orchestrator-api/values-prod-secrets.yaml

# 3. Never commit this file
git status  # Should show it as untracked (not staged)
```

### Alternative: Using Helm Set

You can provide secrets directly via the command line without creating a file:

```bash
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  -f charts/orchestrator-api/values-dev.yaml \
  --set slackWebhook.url="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### Alternative: Using Environment Variables

```bash
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  -f charts/orchestrator-api/values-dev.yaml \
  --set slackWebhook.url="$SLACK_WEBHOOK_URL"
```

### Kubernetes Secret Creation

The chart automatically creates a Kubernetes Secret named `slack-webhook` from the provided URL:

```yaml
# Generated Secret (in Kubernetes)
apiVersion: v1
kind: Secret
metadata:
  name: slack-webhook
  namespace: orchestrator
type: Opaque
stringData:
  webhook-url: <your-webhook-url>
```

This secret is then mounted in deployments:
- `deployment-api.yaml`: orchestrator-api pod
  - Environment variable: `SLACK_WEBHOOK_URL` (from secret)
- `deployment-consumer.yaml`: status-consumer pod
  - Environment variable: `SLACK_WEBHOOK_URL` (from secret)

## Configuration

### Core Environment Variables

| Variable | Example | Description |
|----------|---------|-------------|
| `KAFKA_BROKERS` | `kafka:9092` | Kafka broker endpoint |
| `TOPIC_REQUESTS` | `thinklabs.mlops.request` | Kafka topic for requests |
| `TOPIC_STATUS` | `thinklabs.mlops.status` | Kafka topic for status updates |
| `TOPIC_RESPONSE` | `thinklabs.mlops.response` | Kafka topic for responses |
| `REDIS_ADDR` | `redis-service.redis:6379` | Redis connection address |
| `OTEL_ENV` | `dev` | OTEL environment tag |
| `SLACK_NOTIFY_STATUSES` | `FAILED,SUCCEEDED,PENDING` | Which statuses trigger Slack notifications |

### Slack Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `slackWebhook.enabled` | `false` | Enable/disable Slack notifications |
| `slackWebhook.url` | `""` | Slack incoming webhook URL (secret) |

### Replicas & Resources

```bash
# Development (default)
replicaCount: 2  # orchestrator-api replicas

# Adjust CPU/memory limits
helm install orchestrator charts/orchestrator-api \
  --set resources.api.limits.cpu=1000m \
  --set resources.api.limits.memory=1024Mi
```

## Deployment Examples

### Upgrade Existing Release

```bash
helm upgrade orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  -f charts/orchestrator-api/values-dev.yaml \
  -f charts/orchestrator-api/values-dev-secrets.yaml
```

### Dry-Run to Validate

```bash
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  -f charts/orchestrator-api/values-dev.yaml \
  -f charts/orchestrator-api/values-dev-secrets.yaml \
  --dry-run --debug
```

### Check Deployed Configuration

```bash
# View generated manifests
kubectl get deployment orchestrator-api -n orchestrator -o yaml

# Check Slack webhook secret is mounted
kubectl describe pod -n orchestrator -l app=orchestrator-api | grep -A5 webhook

# Verify secret exists
kubectl get secret slack-webhook -n orchestrator
kubectl get secret slack-webhook -n orchestrator -o jsonpath='{.data.webhook-url}' | base64 -d
```

## Helm Linting & Validation

```bash
# Lint chart syntax
helm lint charts/orchestrator-api

# Validate manifests
helm template orchestrator charts/orchestrator-api \
  -f charts/orchestrator-api/values-dev.yaml

# Install with dry-run (no actual deployment)
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  --create-namespace \
  -f charts/orchestrator-api/values-dev.yaml \
  -f charts/orchestrator-api/values-dev-secrets.yaml \
  --dry-run --debug
```

## File Structure

```
charts/orchestrator-api/
├── Chart.yaml                           # Chart metadata
├── values.yaml                          # Default values
├── values-dev.yaml                      # Development environment values
├── values-prod.yaml                     # Production environment values
├── values-dev-secrets.template.yaml     # Dev secrets template (NEVER commit actual)
├── values-prod-secrets.template.yaml    # Prod secrets template (NEVER commit actual)
├── README.md                            # This file
├── templates/
│   ├── namespace.yaml                   # Kubernetes namespace
│   ├── secret.yaml                      # Slack webhook secret (templated)
│   ├── deployment-api.yaml              # orchestrator-api deployment
│   ├── deployment-consumer.yaml         # status-consumer deployment
│   ├── service.yaml                     # Kubernetes service
│   ├── ingress.yaml                     # Ingress configuration
│   ├── job.yaml                         # Kafka topic creation job
│   └── serviceaccount.yaml              # Service account for Workload Identity
```

## Important Notes

### Security Best Practices

1. **Never commit secrets**: Template files provide reference only
2. **Use separate secret values files**: Keep `values-*-secrets.yaml` local
3. **Rotate credentials regularly**: Update Slack webhooks periodically
4. **Audit secret usage**: Check Kubernetes secret access logs
5. **Use Secret storage**: Consider Sealed Secrets or External Secrets for GitOps

### Git Ignore Patterns

The repository `.gitignore` includes:
```
*-secrets.yaml        # All environment-specific secrets files
values-secrets.yaml   # Generic secrets file
```

This prevents accidental commits of sensitive values.

### CI/CD Integration

For production CI/CD pipelines:

```bash
# In your CI/CD pipeline (GitHub Actions, GitLab CI, etc.)
helm install orchestrator charts/orchestrator-api \
  --namespace orchestrator \
  -f charts/orchestrator-api/values-prod.yaml \
  --set slackWebhook.url="$SLACK_WEBHOOK_URL"  # From CI variables
```

**Never store actual credentials in CI files - use CI secret management instead.**

## Troubleshooting

### Secret Not Found

```bash
# Check if secret exists
kubectl get secret slack-webhook -n orchestrator

# Create manually if missing
kubectl create secret generic slack-webhook \
  --from-literal=webhook-url='https://hooks.slack.com/services/...' \
  --namespace orchestrator
```

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n orchestrator

# View pod logs
kubectl logs -n orchestrator deployment/orchestrator-api

# Describe pod for events
kubectl describe pod -n orchestrator -l app=orchestrator-api
```

### Configuration Not Applied

```bash
# Verify configmap/values
helm get values orchestrator -n orchestrator

# Check environment variables in running pods
kubectl exec -it -n orchestrator \
  deployment/orchestrator-api -- env | grep SLACK
```

## Support

For issues or questions, contact the MLOps team or refer to the main platform documentation.
