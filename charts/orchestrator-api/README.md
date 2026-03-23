# ThinkLabs Orchestrator Helm Chart

This chart deploys the orchestrator API and status-consumer to the `thinklabs-orchestrator` namespace.

## Prerequisites
- Kafka and Prometheus must already be running (external)
- Kubernetes cluster (EKS)
- NGINX Ingress Controller (or compatible)

## Install

1. Package and push your Docker images for orchestrator-api and status-consumer.
2. Edit `values.yaml` to set your image repositories, tags, tenant, environment, and Kafka bootstrap address.
3. Install the chart:

```sh
helm install orchestrator charts/thinklabs-orchestrator --namespace thinklabs-orchestrator --create-namespace \
  --set tenant=mytenant --set environment=dev --set kafka.bootstrap=my-kafka-bootstrap.kafka:9092
```

## Configuration
- `tenant` and `environment` are configurable and injected as env vars.
- Ingress is enabled by default for `dev.service.thinklabs.ai`.
- All environment variables for the Go apps are set in `values.yaml`.
- Slack integration, Redis, and OTEL endpoints are configurable.
- Kafka topics for the tenant are created automatically by a Kubernetes Job using the Kafka CLI.

## Example values.yaml
```yaml
namespace: thinklabs-orchestrator
tenant: mytenant
environment: dev
image:
  repository: <your-docker-repo>/orchestrator-api
  tag: latest
statusConsumerImage:
  repository: <your-docker-repo>/status-consumer
  tag: latest
kafka:
  bootstrap: my-kafka-bootstrap.kafka:9092
```

## Notes
- Kafka and Prometheus are not deployed by this chart.
- The CLI can be run from any environment with network access to the API Ingress.
- For production, set proper image tags and secrets.
- The Kafka topic creation Job requires network access to the Kafka bootstrap service and the ability to resolve the DNS name.
