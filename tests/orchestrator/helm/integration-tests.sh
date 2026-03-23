#!/bin/bash

##############################################################################
# Orchestrator API Integration Tests
# Tests Kafka, Redis, and API endpoint connectivity
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

NAMESPACE="${1:-thinklabs-orchestrator}"
TIMEOUT="${2:-30}"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

##############################################################################
# Utility Functions
##############################################################################

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[→]${NC} $1"
    ((TESTS_SKIPPED++))
}

log_info() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

##############################################################################
# Kafka Tests
##############################################################################

test_kafka_connectivity() {
    print_header "KAFKA CONNECTIVITY TESTS"
    
    log_test "Checking Kafka broker configuration"
    
    # Get the API pod
    local api_pod=$(kubectl get pods -n "$NAMESPACE" -l app=orchestrator-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$api_pod" ]; then
        log_skip "No orchestrator-api pods found"
        return 1
    fi
    
    log_info "Using pod: $api_pod"
    
    # Get Kafka broker from env
    local kafka_brokers=$(kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c 'echo $KAFKA_BROKERS' 2>/dev/null)
    
    if [ -z "$kafka_brokers" ]; then
        log_error "Could not retrieve KAFKA_BROKERS from pod"
        return 1
    fi
    
    log_success "Kafka brokers found: $kafka_brokers"
    
    # Test Kafka connection from pod
    log_test "Testing Kafka TCP connectivity from pod"
    
    local broker_host=$(echo "$kafka_brokers" | cut -d: -f1)
    local broker_port=$(echo "$kafka_brokers" | cut -d: -f2)
    
    if kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c "timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$broker_host/$broker_port' 2>/dev/null"; then
        log_success "Kafka broker is reachable at $broker_host:$broker_port"
    else
        log_error "Cannot reach Kafka broker at $broker_host:$broker_port"
        return 1
    fi
}

test_kafka_topics() {
    print_header "KAFKA TOPICS TESTS"
    
    log_test "Verifying Kafka topics exist"
    
    local api_pod=$(kubectl get pods -n "$NAMESPACE" -l app=orchestrator-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$api_pod" ]; then
        log_skip "No orchestrator-api pods found"
        return 1
    fi
    
    # Get topic names from environment
    local topic_requests=$(kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c 'echo $TOPIC_REQUESTS' 2>/dev/null)
    local topic_status=$(kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c 'echo $TOPIC_STATUS' 2>/dev/null)
    local topic_response=$(kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c 'echo $TOPIC_RESPONSE' 2>/dev/null)
    
    log_info "Expected topics:"
    log_info "  Requests: $topic_requests"
    log_info "  Status: $topic_status"
    log_info "  Response: $topic_response"
    
    # Note: Actual topic verification requires Kafka CLI tools which may not be available in the pod
    log_warning "Topic verification skipped (requires Kafka CLI tools in pod)"
}

##############################################################################
# Redis Tests
##############################################################################

test_redis_connectivity() {
    print_header "REDIS CONNECTIVITY TESTS"
    
    log_test "Checking Redis configuration"
    
    local api_pod=$(kubectl get pods -n "$NAMESPACE" -l app=orchestrator-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$api_pod" ]; then
        log_skip "No orchestrator-api pods found"
        return 1
    fi
    
    # Get Redis address from env
    local redis_addr=$(kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c 'echo $REDIS_ADDR' 2>/dev/null)
    
    if [ -z "$redis_addr" ] || [ "$redis_addr" == "null" ]; then
        log_warning "Redis not configured (STATUS_STORE may not be set to 'redis')"
        return 0
    fi
    
    log_success "Redis address found: $redis_addr"
    
    # Test Redis connection
    log_test "Testing Redis TCP connectivity from pod"
    
    local redis_host=$(echo "$redis_addr" | cut -d: -f1)
    local redis_port=$(echo "$redis_addr" | cut -d: -f2)
    
    if kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c "timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$redis_host/$redis_port' 2>/dev/null"; then
        log_success "Redis is reachable at $redis_host:$redis_port"
    else
        log_error "Cannot reach Redis at $redis_host:$redis_port"
        return 1
    fi
    
    # Test Redis PING command
    log_test "Testing Redis PING command"
    
    if kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c "echo PING | timeout 5 nc -w 1 $redis_host $redis_port 2>/dev/null | grep -q PING"; then
        log_success "Redis PING command successful"
    else
        log_warning "Could not verify Redis PING (nc may not be available in pod)"
    fi
}

##############################################################################
# API Endpoint Tests
##############################################################################

test_api_health_endpoints() {
    print_header "API HEALTH ENDPOINT TESTS"
    
    # Get API service
    local api_service=$(kubectl get svc -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.labels.app=="orchestrator-api")].metadata.name}' 2>/dev/null)
    
    if [ -z "$api_service" ]; then
        log_skip "No orchestrator-api service found"
        return 1
    fi
    
    log_info "Using service: $api_service"
    
    # Kill any existing port-forward
    pkill -f "kubectl port-forward.*$api_service" 2>/dev/null || true
    sleep 1
    
    # Start port-forward in background
    log_test "Setting up port-forward to service"
    kubectl port-forward -n "$NAMESPACE" "svc/$api_service" 8080:8080 > /dev/null 2>&1 &
    local pf_pid=$!
    
    # Wait for port-forward to establish
    sleep 2
    
    local api_url="http://localhost:8080"
    
    trap "kill $pf_pid 2>/dev/null || true" EXIT
    
    # Test health endpoint
    log_test "Testing GET /healthz endpoint"
    
    local response=$(curl -s -w "\n%{http_code}" "$api_url/healthz" 2>/dev/null || echo -e "\n000")
    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" == "200" ]; then
        log_success "Health endpoint responding (HTTP 200)"
        log_info "Response: $body"
    else
        log_error "Health endpoint returned HTTP $http_code"
        log_info "Response: $body"
    fi
    
    # Test readiness endpoint
    log_test "Testing GET /readyz endpoint"
    
    local response=$(curl -s -w "\n%{http_code}" "$api_url/readyz" 2>/dev/null || echo -e "\n000")
    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" == "200" ]; then
        log_success "Readiness endpoint responding (HTTP 200)"
        log_info "Response: $body"
    else
        log_error "Readiness endpoint returned HTTP $http_code"
        log_info "Response: $body"
    fi
}

test_api_inference_endpoints() {
    print_header "API INFERENCE ENDPOINT TESTS"
    
    # Get API service
    local api_service=$(kubectl get svc -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.labels.app=="orchestrator-api")].metadata.name}' 2>/dev/null)
    
    if [ -z "$api_service" ]; then
        log_skip "No orchestrator-api service found"
        return 1
    fi
    
    # Kill any existing port-forward
    pkill -f "kubectl port-forward.*$api_service" 2>/dev/null || true
    sleep 1
    
    # Start port-forward
    kubectl port-forward -n "$NAMESPACE" "svc/$api_service" 8080:8080 > /dev/null 2>&1 &
    local pf_pid=$!
    
    sleep 2
    
    local api_url="http://localhost:8080"
    
    trap "kill $pf_pid 2>/dev/null || true" EXIT
    
    # Test inference endpoint
    log_test "Testing POST /v1/inference endpoint"
    
    local payload='{
      "model_name": "test-model",
      "inputs": {
        "input_1": 1.0
      }
    }'
    
    local response=$(curl -s -w "\n%{http_code}" -X POST "$api_url/v1/inference" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo -e "\n000")
    
    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" == "200" ] || [ "$http_code" == "201" ] || [ "$http_code" == "202" ] || [ "$http_code" == "400" ]; then
        log_success "Inference endpoint responding (HTTP $http_code)"
        log_info "Response: $(echo "$body" | jq . 2>/dev/null || echo "$body")"
        
        # Check if we got a run_id back
        if echo "$body" | jq -e '.run_id' > /dev/null 2>&1; then
            local run_id=$(echo "$body" | jq -r '.run_id')
            log_success "Got run_id from inference: $run_id"
            
            # Test get run status
            log_test "Testing GET /v1/runs/{run_id} endpoint"
            
            local response=$(curl -s -w "\n%{http_code}" "$api_url/v1/runs/$run_id" 2>/dev/null || echo -e "\n000")
            local status_http_code=$(echo "$response" | tail -n 1)
            local status_body=$(echo "$response" | head -n -1)
            
            if [ "$status_http_code" == "200" ] || [ "$status_http_code" == "404" ]; then
                log_success "Get run status endpoint responding (HTTP $status_http_code)"
                log_info "Response: $(echo "$status_body" | jq . 2>/dev/null || echo "$status_body")"
            else
                log_error "Get run status endpoint returned HTTP $status_http_code"
            fi
        fi
    else
        log_error "Inference endpoint returned HTTP $http_code"
        log_info "Response: $body"
    fi
}

##############################################################################
# OpenTelemetry Tests
##############################################################################

test_otel_connectivity() {
    print_header "OPENTELEMETRY CONNECTIVITY TESTS"
    
    log_test "Checking OTEL configuration"
    
    local api_pod=$(kubectl get pods -n "$NAMESPACE" -l app=orchestrator-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$api_pod" ]; then
        log_skip "No orchestrator-api pods found"
        return 1
    fi
    
    # Get OTEL endpoint from env
    local otel_endpoint=$(kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c 'echo $OTEL_EXPORTER_OTLP_ENDPOINT' 2>/dev/null)
    
    if [ -z "$otel_endpoint" ] || [ "$otel_endpoint" == "null" ]; then
        log_warning "OTEL endpoint not configured"
        return 0
    fi
    
    log_success "OTEL endpoint found: $otel_endpoint"
    
    # Test OTEL connectivity
    local otel_host=$(echo "$otel_endpoint" | sed 's|http://||' | sed 's|https://||' | cut -d: -f1)
    local otel_port=$(echo "$otel_endpoint" | sed 's|http://||' | sed 's|https://||' | cut -d: -f2)
    
    log_test "Testing OTEL endpoint connectivity"
    
    if kubectl exec -n "$NAMESPACE" "$api_pod" -- sh -c "timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$otel_host/$otel_port' 2>/dev/null"; then
        log_success "OTEL collector is reachable at $otel_host:$otel_port"
    else
        log_warning "Cannot reach OTEL collector at $otel_host:$otel_port (may not be critical)"
    fi
}

##############################################################################
# Deployment Event Checks
##############################################################################

check_deployment_events() {
    print_header "DEPLOYMENT EVENT ANALYSIS"
    
    log_test "Checking for deployment issues"
    
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for deployment in $deployments; do
        log_info "Checking events for deployment: $deployment"
        
        # Get recent events
        local events=$(kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$deployment" --sort-by='.lastTimestamp' 2>/dev/null)
        
        if echo "$events" | grep -i "error\|failed\|warning" > /dev/null; then
            log_warning "Found error/warning events for deployment:"
            echo "$events" | grep -i "error\|failed\|warning" | sed 's/^/  /'
        else
            log_success "No error events found for deployment"
        fi
    done
}

##############################################################################
# Summary Report
##############################################################################

print_summary() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}TEST SUMMARY${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed! The orchestrator API appears to be working correctly.${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed. Please review the output above.${NC}"
        return 1
    fi
}

##############################################################################
# Main Execution
##############################################################################

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Orchestrator API Integration Test Suite                ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo "Timeout: ${TIMEOUT}s"
    echo ""
    
    test_kafka_connectivity
    test_kafka_topics
    test_redis_connectivity
    test_otel_connectivity
    test_api_health_endpoints
    test_api_inference_endpoints
    check_deployment_events
    print_summary
    
    echo ""
}

main
