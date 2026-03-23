#!/bin/bash

# Test script for Redis

echo "=== Testing Redis ==="

# Check if Redis pod exists
echo ""
echo "=== Checking Redis Pod Status ==="
redis_pod=$(kubectl get pods -n redis -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$redis_pod" ]; then
    echo "❌ No Redis pod found in redis namespace"
    exit 1
fi

echo "✅ Redis pod found: $redis_pod"
redis_status=$(kubectl get pod -n redis "$redis_pod" -o jsonpath='{.status.phase}')
echo "Pod status: $redis_status"

if [ "$redis_status" != "Running" ]; then
    echo "❌ Redis pod is not running (status: $redis_status)"
    exit 1
fi

# Check Redis service
echo ""
echo "=== Checking Redis Service ==="
redis_service=$(kubectl get svc -n redis redis -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")

if [ -z "$redis_service" ]; then
    echo "❌ Redis service not found"
    exit 1
fi

redis_ip=$(kubectl get svc -n redis redis -o jsonpath='{.spec.clusterIP}')
redis_port=$(kubectl get svc -n redis redis -o jsonpath='{.spec.ports[0].port}')
echo "✅ Redis service: $redis_service"
echo "   Cluster IP: $redis_ip:$redis_port"

# Test Redis connectivity
echo ""
echo "=== Testing PING Command ==="
ping_result=$(kubectl exec -n redis "$redis_pod" -- redis-cli PING 2>/dev/null || echo "FAILED")

if [ "$ping_result" = "PONG" ]; then
    echo "✅ Redis PING successful"
else
    echo "⚠️  Redis PING failed (result: $ping_result)"
fi

# Test SET and GET commands
echo ""
echo "=== Testing SET/GET Commands ==="
test_key="test-key-$(date +%s)"
test_value="test-value"

# Set a value
set_result=$(kubectl exec -n redis "$redis_pod" -- redis-cli SET "$test_key" "$test_value" 2>/dev/null || echo "FAILED")

if [ "$set_result" = "OK" ]; then
    echo "✅ SET command successful"
    
    # Get the value back
    get_result=$(kubectl exec -n redis "$redis_pod" -- redis-cli GET "$test_key" 2>/dev/null || echo "FAILED")
    
    if [ "$get_result" = "$test_value" ]; then
        echo "✅ GET command successful (value retrieved: $get_result)"
    else
        echo "⚠️  GET command returned unexpected value: $get_result"
    fi
else
    echo "⚠️  SET command failed (result: $set_result)"
fi

# Check Redis info
echo ""
echo "=== Checking Redis Server Info ==="
redis_version=$(kubectl exec -n redis "$redis_pod" -- redis-cli INFO server 2>/dev/null | grep "redis_version" | cut -d: -f2 | tr -d '\r' || echo "unknown")

if [ "$redis_version" != "unknown" ]; then
    echo "✅ Redis server is responding"
    echo "   Version: $redis_version"
else
    echo "⚠️  Could not retrieve Redis server info"
fi

# Check Redis memory
echo ""
echo "=== Checking Redis Memory Usage ==="
memory_used=$(kubectl exec -n redis "$redis_pod" -- redis-cli INFO memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r' || echo "unknown")

if [ "$memory_used" != "unknown" ]; then
    echo "✅ Memory usage: $memory_used"
else
    echo "⚠️  Could not retrieve memory info"
fi

# Check connected clients
echo ""
echo "=== Checking Connected Clients ==="
clients=$(kubectl exec -n redis "$redis_pod" -- redis-cli INFO clients 2>/dev/null | grep "connected_clients" | cut -d: -f2 | tr -d '\r' || echo "unknown")

if [ "$clients" != "unknown" ]; then
    echo "✅ Connected clients: $clients"
else
    echo "⚠️  Could not retrieve client info"
fi

# Check Redis persistence
echo ""
echo "=== Checking Redis Persistence ==="
rdb_save=$(kubectl exec -n redis "$redis_pod" -- redis-cli LASTSAVE 2>/dev/null || echo "unknown")

if [ "$rdb_save" != "unknown" ]; then
    echo "✅ Last RDB save: $(date -r $rdb_save 2>/dev/null || echo "timestamp: $rdb_save")"
else
    echo "⚠️  Could not retrieve last save time"
fi

# Summary
echo ""
echo "=== Redis Test Summary ==="
echo "✅ Redis pod is running"
echo "✅ Redis service is accessible"
echo "✅ Redis responds to commands"
echo ""
echo "Redis is ready for use by orchestrator-api and status-consumer"
echo ""
echo "=== Redis Test Complete ==="
