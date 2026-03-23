#!/bin/bash

# Test script for Kafka connectivity and topics
set -e

echo "=== Testing Kafka Connectivity ==="

KAFKA_BROKER="kafka-kafka.kafka:9092"
KAFKA_TOPICS=("thinklabs.mlops.request" "thinklabs.mlops.status" "thinklabs.mlops.response")

# Test broker connectivity via kubectl exec
echo "Testing broker connectivity via kubectl..."
if kubectl exec -n kafka kafka-kafka-0 -- nc -z localhost 9092; then
    echo "✅ Kafka broker is reachable on localhost:9092"
else
    echo "❌ Kafka broker is NOT reachable"
    exit 1
fi

# Test topics exist
echo ""
echo "=== Checking Kafka Topics ==="
for topic in "${KAFKA_TOPICS[@]}"; do
    echo ""
    echo "Topic: $topic"
    # List all topics and check if our topic exists
    kafka_topics=$(kubectl exec -n kafka kafka-kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null || echo "")
    if echo "$kafka_topics" | grep -q "$topic"; then
        echo "✅ Topic exists"
        # Get topic details
        kubectl exec -n kafka kafka-kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$topic"
    else
        echo "❌ Topic does NOT exist"
    fi
done

echo ""
echo "=== Kafka Test Complete ==="
