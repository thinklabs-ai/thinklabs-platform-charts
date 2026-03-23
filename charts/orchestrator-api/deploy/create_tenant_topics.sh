#!/bin/bash
# Usage: ./create_tenant_topics.sh <tenant> <brokers>
TENANT="$1"
BROKERS="$2"

for TOPIC in request status response; do
  kafka-topics --bootstrap-server "$BROKERS" --create --if-not-exists --topic "${TENANT}.mlops.${TOPIC}" --partitions 1 --replication-factor 1
done
