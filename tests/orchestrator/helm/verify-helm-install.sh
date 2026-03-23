#!/bin/bash

##############################################################################
# Orchestrator API Helm Installation Verification Script
# This script verifies the helm installation and tests all components
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
NAMESPACE="${1:-thinklabs-orchestrator}"
RELEASE_NAME="${2:-orchestrator}"
CHART_PATH="charts/orchestrator-api"
KUBECONFIG="${3:-$HOME/.kube/config}"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

##############################################################################
# Utility Functions
##############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

##############################################################################
# Pre-flight Checks
##############################################################################

check_prerequisites() {
    print_header "PRE-FLIGHT CHECKS"
    
    # Check kubectl
    if command -v kubectl &> /dev/null; then
        log_success "kubectl is installed"
    else
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Check helm
    if command -v helm &> /dev/null; then
        log_success "helm is installed"
    else
        log_error "helm is not installed"
        exit 1
    fi
    
    # Check kubeconfig
    if [ -f "$KUBECONFIG" ]; then
        log_success "kubeconfig found at $KUBECONFIG"
    else
        log_error "kubeconfig not found at $KUBECONFIG"
        exit 1
    fi
    
    # Check cluster connection
    if kubectl cluster-info &> /dev/null; then
        log_success "Connected to Kubernetes cluster"
    else
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if namespace exists
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_success "Namespace '$NAMESPACE' exists"
    else
        log_warning "Namespace '$NAMESPACE' does not exist - it will be created"
    fi
}

##############################################################################
# Helm Chart Validation
##############################################################################

validate_helm_chart() {
    print_header "HELM CHART VALIDATION"
    
    # Check if chart path exists
    if [ ! -d "$CHART_PATH" ]; then
        log_error "Chart path '$CHART_PATH' not found"
        return 1
    fi
    log_success "Chart directory found at $CHART_PATH"
    
    # Validate chart syntax
    if helm lint "$CHART_PATH" > /tmp/helm-lint.log 2>&1; then
        log_success "Helm chart linting passed"
    else
        log_error "Helm chart linting failed"
        cat /tmp/helm-lint.log
        return 1
    fi
    
    # Validate chart structure
    if [ -f "$CHART_PATH/Chart.yaml" ]; then
        log_success "Chart.yaml found"
    else
        log_error "Chart.yaml not found"
        return 1
    fi
    
    if [ -f "$CHART_PATH/values.yaml" ]; then
        log_success "values.yaml found"
    else
        log_error "values.yaml not found"
        return 1
    fi
}

##############################################################################
# Template Rendering
##############################################################################

render_templates() {
    print_header "HELM TEMPLATE RENDERING"
    
    # Test template rendering with default values
    if helm template "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        > /tmp/manifest.yaml 2>/tmp/template-error.log; then
        log_success "Templates rendered successfully"
        log_info "Generated manifest has $(wc -l < /tmp/manifest.yaml) lines"
    else
        log_error "Template rendering failed"
        cat /tmp/template-error.log
        return 1
    fi
    
    # Check for required resources in template
    local required_resources=("Deployment" "Service" "ServiceAccount" "Job")
    for resource in "${required_resources[@]}"; do
        if grep -q "kind: $resource" /tmp/manifest.yaml; then
            log_success "Found required '$resource' in templates"
        else
            log_warning "Did not find '$resource' in templates"
        fi
    done
}

##############################################################################
# Helm Release Status
##############################################################################

check_helm_release() {
    print_header "HELM RELEASE STATUS"
    
    # Check if release is installed
    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        log_success "Helm release '$RELEASE_NAME' is installed"
        
        # Get release details
        local release_status=$(helm status "$RELEASE_NAME" -n "$NAMESPACE" 2>&1 | grep -i status | head -1)
        log_info "Release Status: $release_status"
        
        # Get release values
        log_info "Release values:"
        helm get values "$RELEASE_NAME" -n "$NAMESPACE" | sed 's/^/  /'
    else
        log_warning "Helm release '$RELEASE_NAME' is not installed"
        log_info "To install, run: helm install $RELEASE_NAME $CHART_PATH -n $NAMESPACE --create-namespace"
        return 1
    fi
}

##############################################################################
# Deployment Status
##############################################################################

check_deployments() {
    print_header "DEPLOYMENT STATUS"
    
    # Get all deployments in namespace
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$deployments" ]; then
        log_warning "No deployments found in namespace '$NAMESPACE'"
        return 1
    fi
    
    for deployment in $deployments; do
        log_info "Checking deployment: $deployment"
        
        local desired=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
        local ready=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        local available=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}')
        
        if [ "$ready" == "$desired" ] && [ "$available" == "$desired" ]; then
            log_success "Deployment '$deployment' is ready ($ready/$desired)"
        else
            log_error "Deployment '$deployment' is not ready ($ready/$desired available: $available)"
        fi
        
        # Check pod status
        local pods=$(kubectl get pods -n "$NAMESPACE" -l app="$deployment" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
        for pod in $pods; do
            local pod_status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
            if [ "$pod_status" == "Running" ]; then
                log_success "Pod '$pod' is running"
            else
                log_error "Pod '$pod' status is $pod_status"
            fi
        done
    done
}

##############################################################################
# Service Status
##############################################################################

check_services() {
    print_header "SERVICE STATUS"
    
    local services=$(kubectl get services -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$services" ]; then
        log_warning "No services found in namespace '$NAMESPACE'"
        return 1
    fi
    
    for service in $services; do
        log_info "Checking service: $service"
        
        local service_type=$(kubectl get service "$service" -n "$NAMESPACE" -o jsonpath='{.spec.type}')
        local cluster_ip=$(kubectl get service "$service" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
        
        log_success "Service '$service' ($service_type): $cluster_ip"
        
        # Check endpoints
        local endpoints=$(kubectl get endpoints "$service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
        if [ -n "$endpoints" ]; then
            log_success "Service '$service' has active endpoints: $endpoints"
        else
            log_warning "Service '$service' has no active endpoints"
        fi
    done
}

##############################################################################
# Kafka Connectivity Test
##############################################################################

test_kafka_connectivity() {
    print_header "KAFKA CONNECTIVITY TEST"
    
    # Get Kafka broker address from deployment
    local kafka_broker=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath='{.items[0].spec.template.spec.containers[0].env[?(@.name=="KAFKA_BROKERS")].value}' 2>/dev/null)
    
    if [ -z "$kafka_broker" ]; then
        log_warning "Could not determine Kafka broker from deployment"
        return 1
    fi
    
    log_info "Kafka broker: $kafka_broker"
    
    # Try to test connection from a pod
    local pod=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$pod" ]; then
        log_info "Testing Kafka connectivity from pod: $pod"
        
        # Check if we can resolve Kafka broker
        if kubectl exec -n "$NAMESPACE" "$pod" -- sh -c "nc -zv $kafka_broker 2>&1 | grep -q succeeded"; then
            log_success "Kafka broker is reachable from pod"
        else
            log_warning "Could not verify Kafka connectivity from pod (nc may not be available)"
        fi
    fi
}

##############################################################################
# Redis Connectivity Test
##############################################################################

test_redis_connectivity() {
    print_header "REDIS CONNECTIVITY TEST"
    
    # Get Redis address from deployment
    local redis_addr=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath='{.items[0].spec.template.spec.containers[0].env[?(@.name=="REDIS_ADDR")].value}' 2>/dev/null)
    
    if [ -z "$redis_addr" ]; then
        log_warning "Redis not configured or not found in deployment"
        return 1
    fi
    
    log_info "Redis address: $redis_addr"
    
    # Try to test connection from a pod
    local pod=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$pod" ]; then
        log_info "Testing Redis connectivity from pod: $pod"
        
        if kubectl exec -n "$NAMESPACE" "$pod" -- sh -c "echo PING | nc -w 1 ${redis_addr%:*} ${redis_addr##*:}" > /dev/null 2>&1; then
            log_success "Redis is reachable from pod"
        else
            log_warning "Could not verify Redis connectivity from pod"
        fi
    fi
}

##############################################################################
# API Endpoint Tests
##############################################################################

test_api_endpoints() {
    print_header "API ENDPOINT TESTS"
    
    # Port-forward to API service
    local api_service="${RELEASE_NAME}-api"
    local api_port=8080
    
    log_info "Setting up port-forward to service: $api_service"
    
    # Kill any existing port-forward
    pkill -f "kubectl port-forward.*$api_service" 2>/dev/null || true
    
    # Start new port-forward in background
    kubectl port-forward -n "$NAMESPACE" "svc/$api_service" $api_port:$api_port > /dev/null 2>&1 &
    local pf_pid=$!
    
    # Wait for port-forward to establish
    sleep 2
    
    # Test health endpoint
    log_info "Testing /healthz endpoint"
    if curl -s -f http://localhost:$api_port/healthz > /dev/null; then
        log_success "Health endpoint is responding"
    else
        log_error "Health endpoint is not responding"
    fi
    
    # Test readiness endpoint
    log_info "Testing /readyz endpoint"
    if curl -s -f http://localhost:$api_port/readyz > /dev/null; then
        log_success "Readiness endpoint is responding"
    else
        log_error "Readiness endpoint is not responding"
    fi
    
    # Test inference endpoint with sample payload
    log_info "Testing POST /v1/inference endpoint"
    local response=$(curl -s -X POST http://localhost:$api_port/v1/inference \
        -H "Content-Type: application/json" \
        -d '{"model_name":"test-model","inputs":{"input_1":1.0}}' \
        -w "\n%{http_code}" 2>/dev/null || echo "000")
    
    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ] || [ "$http_code" -eq 202 ]; then
        log_success "Inference endpoint is responding (HTTP $http_code)"
        log_info "Response: $body"
    else
        log_error "Inference endpoint returned HTTP $http_code"
        log_info "Response: $body"
    fi
    
    # Clean up port-forward
    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true
}

##############################################################################
# Configuration Validation
##############################################################################

validate_configuration() {
    print_header "CONFIGURATION VALIDATION"
    
    # Get deployment environment variables
    local deployment=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$deployment" ]; then
        log_warning "No deployments found"
        return 1
    fi
    
    log_info "Validating configuration for deployment: $deployment"
    
    # Check required environment variables
    local required_envs=("KAFKA_BROKERS" "TOPIC_REQUESTS" "TOPIC_STATUS" "OTEL_EXPORTER_OTLP_ENDPOINT")
    
    for env_var in "${required_envs[@]}"; do
        local env_value=$(kubectl get deployment "$deployment" -n "$NAMESPACE" \
            -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"$env_var\")].value}" 2>/dev/null)
        
        if [ -n "$env_value" ]; then
            log_success "Environment variable '$env_var' is set to: $env_value"
        else
            log_warning "Environment variable '$env_var' is not set"
        fi
    done
}

##############################################################################
# Logs Analysis
##############################################################################

check_logs() {
    print_header "LOGS ANALYSIS"
    
    local pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $pods; do
        log_info "Checking logs for pod: $pod"
        
        local error_count=$(kubectl logs -n "$NAMESPACE" "$pod" 2>/dev/null | grep -i error | wc -l)
        local warning_count=$(kubectl logs -n "$NAMESPACE" "$pod" 2>/dev/null | grep -i warning | wc -l)
        
        if [ "$error_count" -gt 0 ]; then
            log_error "Found $error_count errors in pod logs"
            log_warning "Last 5 errors:"
            kubectl logs -n "$NAMESPACE" "$pod" 2>/dev/null | grep -i error | tail -5 | sed 's/^/    /'
        else
            log_success "No errors found in pod logs"
        fi
        
        if [ "$warning_count" -gt 0 ]; then
            log_warning "Found $warning_count warnings in pod logs"
        fi
    done
}

##############################################################################
# Summary Report
##############################################################################

print_summary() {
    print_header "VERIFICATION SUMMARY"
    
    echo ""
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed! The helm installation appears to be working correctly.${NC}"
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
    echo -e "${BLUE}║  Orchestrator API Helm Installation Verification Suite    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo "Release: $RELEASE_NAME"
    echo "Chart: $CHART_PATH"
    echo ""
    
    check_prerequisites
    validate_helm_chart
    render_templates
    check_helm_release
    check_deployments
    check_services
    validate_configuration
    test_kafka_connectivity
    test_redis_connectivity
    test_api_endpoints
    check_logs
    print_summary
    
    echo ""
}

# Run main function
main
