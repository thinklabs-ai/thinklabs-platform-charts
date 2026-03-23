#!/bin/bash

##############################################################################
# Shared Test Utilities
# Common functions used across all test scripts
##############################################################################

# Color definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Counters (global)
export TESTS_PASSED=0
export TESTS_FAILED=0
export TESTS_SKIPPED=0
export TESTS_WARNED=0

##############################################################################
# Logger Functions
##############################################################################

log_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

log_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

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
    ((TESTS_WARNED++))
}

log_skip() {
    echo -e "${YELLOW}[→]${NC} $1"
    ((TESTS_SKIPPED++))
}

log_info() {
    echo -e "${BLUE}[*]${NC} $1"
}

log_debug() {
    if [ "${DEBUG:-0}" == "1" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

##############################################################################
# Test Assertion Functions
##############################################################################

assert_command_exists() {
    local cmd=$1
    local description=${2:-"$cmd"}
    
    if command -v "$cmd" &> /dev/null; then
        log_success "$description is available"
        return 0
    else
        log_error "$description is not installed"
        return 1
    fi
}

assert_file_exists() {
    local file=$1
    local description=${2:-"$file"}
    
    if [ -f "$file" ]; then
        log_success "File exists: $description"
        return 0
    else
        log_error "File not found: $description"
        return 1
    fi
}

assert_directory_exists() {
    local dir=$1
    local description=${2:-"$dir"}
    
    if [ -d "$dir" ]; then
        log_success "Directory exists: $description"
        return 0
    else
        log_error "Directory not found: $description"
        return 1
    fi
}

assert_equals() {
    local actual=$1
    local expected=$2
    local description=${3:-"comparison"}
    
    if [ "$actual" == "$expected" ]; then
        log_success "$description: $actual"
        return 0
    else
        log_error "$description: expected '$expected', got '$actual'"
        return 1
    fi
}

assert_not_empty() {
    local value=$1
    local description=${2:-"value"}
    
    if [ -n "$value" ]; then
        log_success "$description is not empty"
        return 0
    else
        log_error "$description is empty"
        return 1
    fi
}

##############################################################################
# Kubernetes Helper Functions
##############################################################################

k8s_get_pod() {
    local namespace=$1
    local label=$2
    
    kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

k8s_get_service() {
    local namespace=$1
    local label=$2
    
    kubectl get svc -n "$namespace" -l "$label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

k8s_pod_ready() {
    local namespace=$1
    local pod=$2
    
    local status=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)
    [ "$status" == "Running" ]
}

k8s_deployment_ready() {
    local namespace=$1
    local deployment=$2
    
    local desired=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    local ready=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    
    [ -n "$desired" ] && [ -n "$ready" ] && [ "$desired" -eq "$ready" ]
}

k8s_get_env() {
    local namespace=$1
    local pod=$2
    local env_var=$3
    
    kubectl exec -n "$namespace" "$pod" -- sh -c "echo \$$env_var" 2>/dev/null
}

##############################################################################
# Network Helper Functions
##############################################################################

test_tcp_connection() {
    local host=$1
    local port=$2
    
    if bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

test_http_endpoint() {
    local url=$1
    local expected_http=${2:-200}
    
    local response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null || echo -e "\n000")
    local http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq "$expected_http" ] || [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ] || [ "$http_code" -eq 202 ]; then
        return 0
    else
        return 1
    fi
}

##############################################################################
# Report Functions
##############################################################################

print_test_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    
    echo ""
    log_section "TEST SUMMARY"
    echo ""
    echo -e "${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "${YELLOW}Warned:${NC}  $TESTS_WARNED"
    echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo -e "${BLUE}Total:${NC}   $total"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed. Please review the output above.${NC}"
        return 1
    fi
}

##############################################################################
# Cleanup Functions
##############################################################################

cleanup_port_forward() {
    local service=$1
    pkill -f "kubectl port-forward.*$service" 2>/dev/null || true
}

cleanup_all_port_forwards() {
    pkill -f "kubectl port-forward" 2>/dev/null || true
}

# Ensure cleanup runs on exit
trap cleanup_all_port_forwards EXIT

##############################################################################
# Utility Functions
##############################################################################

# Resolve script directory (works with sourcing)
get_script_dir() {
    local script_source="${BASH_SOURCE[0]}"
    local script_dir
    
    while [ -L "$script_source" ]; do
        script_dir=$(cd -P "$(dirname "$script_source")" && pwd)
        script_source=$(readlink "$script_source")
        [[ $script_source != /* ]] && script_source="$script_dir/$script_source"
    done
    
    script_dir=$(cd -P "$(dirname "$script_source")" && pwd)
    echo "$script_dir"
}

# Find root of platform-charts
find_platform_charts_root() {
    local current_dir=$(pwd)
    
    while [ "$current_dir" != "/" ]; do
        if [ -f "$current_dir/Chart.yaml" ] && [ -d "$current_dir/charts" ]; then
            # This might be a chart directory, go up one level
            current_dir=$(dirname "$current_dir")
        fi
        
        if [ -d "$current_dir/charts" ] && [ -d "$current_dir/tests" ]; then
            echo "$current_dir"
            return 0
        fi
        
        current_dir=$(dirname "$current_dir")
    done
    
    echo ""
    return 1
}

# Wait for condition with timeout
wait_for() {
    local timeout=$1
    local cmd=$2
    local description=${3:-"condition"}
    
    local elapsed=0
    local interval=1
    
    while [ $elapsed -lt $timeout ]; do
        if eval "$cmd" > /dev/null 2>&1; then
            return 0
        fi
        
        sleep $interval
        ((elapsed += interval))
    done
    
    log_error "Timeout waiting for: $description ($timeout seconds)"
    return 1
}

##############################################################################
# Export functions so they're available in subshells
##############################################################################

export -f log_header log_section log_test log_success log_error log_warning log_skip log_info log_debug
export -f assert_command_exists assert_file_exists assert_directory_exists assert_equals assert_not_empty
export -f k8s_get_pod k8s_get_service k8s_pod_ready k8s_deployment_ready k8s_get_env
export -f test_tcp_connection test_http_endpoint
export -f print_test_summary cleanup_port_forward cleanup_all_port_forwards
export -f get_script_dir find_platform_charts_root wait_for
