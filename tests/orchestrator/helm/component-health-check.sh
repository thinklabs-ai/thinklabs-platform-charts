#!/bin/bash

##############################################################################
# Orchestrator API Component Health Check
# Tests individual components of the orchestrator API deployment
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${1:-thinklabs-orchestrator}"
OUTPUT_FILE="/tmp/health-check-$(date +%s).log"

# Counters
PASSED=0
FAILED=0

log_info() {
    local msg="[INFO] $1"
    echo -e "${BLUE}$msg${NC}"
    echo "$msg" >> "$OUTPUT_FILE"
}

log_success() {
    local msg="[PASS] $1"
    echo -e "${GREEN}$msg${NC}"
    echo "$msg" >> "$OUTPUT_FILE"
    ((PASSED++))
}

log_error() {
    local msg="[FAIL] $1"
    echo -e "${RED}$msg${NC}"
    echo "$msg" >> "$OUTPUT_FILE"
    ((FAILED++))
}

log_warning() {
    local msg="[WARN] $1"
    echo -e "${YELLOW}$msg${NC}"
    echo "$msg" >> "$OUTPUT_FILE"
}

##############################################################################
# Pod Health Checks
##############################################################################

check_pod_resources() {
    log_info "=== Pod Resource Checks ==="
    
    local pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $pods; do
        log_info "Checking resources for pod: $pod"
        
        # Check CPU and Memory requests/limits
        local cpu_request=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
        local memory_request=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null)
        local cpu_limit=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.limits.cpu}' 2>/dev/null)
        local memory_limit=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null)
        
        if [ -n "$cpu_request" ] && [ -n "$memory_request" ]; then
            log_success "Pod '$pod' has resource requests: CPU=$cpu_request, Memory=$memory_request"
        else
            log_warning "Pod '$pod' has no resource requests defined"
        fi
        
        if [ -n "$cpu_limit" ] && [ -n "$memory_limit" ]; then
            log_success "Pod '$pod' has resource limits: CPU=$cpu_limit, Memory=$memory_limit"
        else
            log_warning "Pod '$pod' has no resource limits defined (recommended for production)"
        fi
    done
}

check_pod_probes() {
    log_info "=== Pod Probe Checks (Health/Readiness) ==="
    
    local pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $pods; do
        log_info "Checking probes for pod: $pod"
        
        # Check liveness probe
        local liveness=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].livenessProbe}' 2>/dev/null)
        if [ -n "$liveness" ] && [ "$liveness" != "null" ]; then
            log_success "Pod '$pod' has liveness probe configured"
        else
            log_warning "Pod '$pod' has no liveness probe (recommended for production)"
        fi
        
        # Check readiness probe
        local readiness=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].readinessProbe}' 2>/dev/null)
        if [ -n "$readiness" ] && [ "$readiness" != "null" ]; then
            log_success "Pod '$pod' has readiness probe configured"
        else
            log_warning "Pod '$pod' has no readiness probe (recommended for production)"
        fi
        
        # Check startup probe
        local startup=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].startupProbe}' 2>/dev/null)
        if [ -n "$startup" ] && [ "$startup" != "null" ]; then
            log_success "Pod '$pod' has startup probe configured"
        fi
    done
}

check_pod_security() {
    log_info "=== Pod Security Checks ==="
    
    local pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $pods; do
        log_info "Checking security context for pod: $pod"
        
        # Check if running as root
        local run_as_user=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null)
        if [ -z "$run_as_user" ] || [ "$run_as_user" == "null" ]; then
            log_warning "Pod '$pod' may be running as root (no runAsUser defined)"
        else
            log_success "Pod '$pod' running as UID: $run_as_user"
        fi
        
        # Check if read-only filesystem
        local read_only=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null)
        if [ "$read_only" == "true" ]; then
            log_success "Pod '$pod' has read-only root filesystem"
        else
            log_warning "Pod '$pod' has writable root filesystem (less secure)"
        fi
        
        # Check for privileged mode
        local privileged=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].securityContext.privileged}' 2>/dev/null)
        if [ "$privileged" != "true" ]; then
            log_success "Pod '$pod' is not running in privileged mode"
        else
            log_warning "Pod '$pod' is running in privileged mode"
        fi
    done
}

##############################################################################
# RBAC Checks
##############################################################################

check_rbac() {
    log_info "=== RBAC Configuration Checks ==="
    
    # Check ServiceAccount
    local sa=$(kubectl get sa -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    if [ -n "$sa" ]; then
        log_success "ServiceAccounts found: $sa"
        
        for service_account in $sa; do
            # Check RoleBindings
            local rolebindings=$(kubectl get rolebinding -n "$NAMESPACE" -o jsonpath="{.items[?(@.subjects[*].name=='$service_account')].metadata.name}" 2>/dev/null)
            if [ -n "$rolebindings" ]; then
                log_success "RoleBindings for ServiceAccount '$service_account': $rolebindings"
            fi
            
            # Check ClusterRoleBindings
            local clusterrolebindings=$(kubectl get clusterrolebinding -o jsonpath="{.items[?(@.subjects[*].name=='$service_account')].metadata.name}" 2>/dev/null)
            if [ -n "$clusterrolebindings" ]; then
                log_success "ClusterRoleBindings for ServiceAccount '$service_account': $clusterrolebindings"
            fi
        done
    else
        log_warning "No ServiceAccounts found in namespace"
    fi
}

##############################################################################
# Network Checks
##############################################################################

check_network_policies() {
    log_info "=== Network Policy Checks ==="
    
    local nps=$(kubectl get networkpolicies -n "$NAMESPACE" 2>/dev/null)
    if [ $? -eq 0 ]; then
        local np_count=$(kubectl get networkpolicies -n "$NAMESPACE" -o jsonpath='{.items | length}' 2>/dev/null)
        if [ "$np_count" -gt 0 ]; then
            log_success "Found $np_count NetworkPolicy resources in namespace"
        else
            log_warning "No NetworkPolicy resources found (consider implementing network segmentation)"
        fi
    else
        log_info "NetworkPolicy support may not be available on this cluster"
    fi
}

##############################################################################
# ConfigMap and Secret Checks
##############################################################################

check_config_resources() {
    log_info "=== ConfigMap and Secret Checks ==="
    
    # Check ConfigMaps
    local cm=$(kubectl get cm -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    if [ -n "$cm" ]; then
        log_success "ConfigMaps found: $cm"
    else
        log_info "No ConfigMaps found in namespace"
    fi
    
    # Check Secrets
    local secrets=$(kubectl get secrets -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    local secret_count=$(echo "$secrets" | wc -w)
    if [ "$secret_count" -gt 1 ]; then
        log_success "Found $secret_count secrets in namespace"
    else
        log_warning "Only 1 or fewer secrets found (check if required secrets are present)"
    fi
}

##############################################################################
# Volume Checks
##############################################################################

check_volumes() {
    log_info "=== Volume Checks ==="
    
    local pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $pods; do
        local volumes=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[*].name}' 2>/dev/null)
        if [ -n "$volumes" ]; then
            log_success "Pod '$pod' has volumes: $volumes"
        else
            log_info "Pod '$pod' has no volumes"
        fi
    done
}

##############################################################################
# Container Image Checks
##############################################################################

check_container_images() {
    log_info "=== Container Image Checks ==="
    
    local pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $pods; do
        local images=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].image}' 2>/dev/null)
        log_info "Pod '$pod' images: $images"
        
        # Check if using 'latest' tag
        if echo "$images" | grep -q ":latest"; then
            log_warning "Pod '$pod' uses ':latest' tag (not recommended for production)"
        else
            log_success "Pod '$pod' uses specific image tags"
        fi
    done
}

##############################################################################
# Affinity and Topology Checks
##############################################################################

check_affinity() {
    log_info "=== Pod Affinity/Topology Checks ==="
    
    local pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $pods; do
        local affinity=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.affinity}' 2>/dev/null)
        if [ -n "$affinity" ] && [ "$affinity" != "null" ]; then
            log_success "Pod '$pod' has affinity rules configured"
        else
            log_warning "Pod '$pod' has no affinity rules (pods may not be well-distributed)"
        fi
    done
}

##############################################################################
# Main Execution
##############################################################################

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Orchestrator API Component Health Check Suite         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo "Output saved to: $OUTPUT_FILE"
    echo ""
    
    : > "$OUTPUT_FILE"  # Clear output file
    
    check_pod_resources
    check_pod_probes
    check_pod_security
    check_rbac
    check_network_policies
    check_config_resources
    check_volumes
    check_container_images
    check_affinity
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo "Summary:"
    echo "  Passed: $PASSED"
    echo "  Failed: $FAILED"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All component checks passed!${NC}"
    else
        echo -e "${RED}Some checks failed. Review the output above.${NC}"
    fi
    
    echo ""
    echo "Full output saved to: $OUTPUT_FILE"
}

main
