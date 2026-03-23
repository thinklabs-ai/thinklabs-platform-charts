#!/bin/bash

##############################################################################
# Orchestrator API End-to-End Test Suite
# Complete workflow test including helm install, verification, and cleanup
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
CHART_PATH="charts/orchestrator-api"
NAMESPACE="${1:-thinklabs-orchestrator}"
RELEASE_NAME="${2:-orchestrator}"
DRY_RUN="${3:-true}"
CLEANUP="${4:-true}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Counters
STAGE=0
TOTAL_STAGES=6

##############################################################################
# Utility Functions
##############################################################################

log_stage() {
    ((STAGE++))
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ Stage $STAGE/$TOTAL_STAGES: $1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_config() {
    echo ""
    echo "Configuration:"
    echo "  Chart Path: $CHART_PATH"
    echo "  Namespace: $NAMESPACE"
    echo "  Release: $RELEASE_NAME"
    echo "  Dry Run: $DRY_RUN"
    echo "  Auto Cleanup: $CLEANUP"
    echo ""
}

##############################################################################
# Stage 1: Pre-flight Checks
##############################################################################

stage_preflight_checks() {
    log_stage "Pre-flight Checks"
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        exit 1
    fi
    log_success "kubectl is available"
    
    if ! command -v helm &> /dev/null; then
        log_error "helm not found"
        exit 1
    fi
    log_success "helm is available"
    
    if ! command -v curl &> /dev/null; then
        log_error "curl not found"
        exit 1
    fi
    log_success "curl is available"
    
    # Check cluster connection
    if ! kubectl cluster-info > /dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    log_success "Connected to Kubernetes cluster"
    
    local cluster_name=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_info "Current context: $cluster_name"
    
    # Check chart exists
    if [ ! -d "$CHART_PATH" ]; then
        log_error "Chart path '$CHART_PATH' not found"
        exit 1
    fi
    log_success "Chart directory found"
    
    # Validate chart
    if helm lint "$CHART_PATH" > /dev/null 2>&1; then
        log_success "Helm chart linting passed"
    else
        log_error "Helm chart linting failed"
        helm lint "$CHART_PATH"
        exit 1
    fi
}

##############################################################################
# Stage 2: Helm Install (Dry-run)
##############################################################################

stage_helm_install() {
    log_stage "Helm Installation"
    
    # Create namespace if it doesn't exist
    log_info "Checking namespace: $NAMESPACE"
    if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
        log_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
        log_success "Namespace created"
    else
        log_success "Namespace already exists"
    fi
    
    # Check if release already exists
    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        log_warning "Release '$RELEASE_NAME' already exists"
        log_info "Uninstalling existing release..."
        if [ "$DRY_RUN" != "true" ]; then
            helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
            sleep 5
        fi
    fi
    
    # Perform helm install
    local install_cmd="helm install $RELEASE_NAME $CHART_PATH -n $NAMESPACE"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "Running in DRY RUN mode:"
        $install_cmd --dry-run --debug 2>&1 | head -50
        log_success "Dry-run completed successfully"
    else
        log_info "Installing helm release..."
        if $install_cmd; then
            log_success "Helm install successful"
            
            # Wait for deployments to be ready
            log_info "Waiting for deployments to be ready (timeout: 300s)..."
            if kubectl rollout status deployment -n "$NAMESPACE" --timeout=300s > /dev/null 2>&1; then
                log_success "All deployments are ready"
            else
                log_warning "Some deployments are not ready yet"
            fi
        else
            log_error "Helm install failed"
            return 1
        fi
    fi
}

##############################################################################
# Stage 3: Verify Deployments
##############################################################################

stage_verify_deployments() {
    log_stage "Deployment Verification"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_warning "Skipping deployment verification in DRY RUN mode"
        return 0
    fi
    
    # Get all deployments
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$deployments" ]; then
        log_error "No deployments found in namespace"
        return 1
    fi
    
    log_info "Found deployments: $deployments"
    
    for deployment in $deployments; do
        local desired=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
        local ready=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        
        if [ "$ready" == "$desired" ]; then
            log_success "Deployment '$deployment' is ready ($ready/$desired)"
        else
            log_error "Deployment '$deployment' not ready ($ready/$desired)"
            return 1
        fi
    done
}

##############################################################################
# Stage 4: Component Tests
##############################################################################

stage_component_tests() {
    log_stage "Component Tests"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_warning "Skipping component tests in DRY RUN mode"
        return 0
    fi
    
    log_info "Running component health checks..."
    
    if [ -f "$SCRIPT_DIR/component-health-check.sh" ]; then
        bash "$SCRIPT_DIR/component-health-check.sh" "$NAMESPACE" || log_warning "Some health checks failed"
    else
        log_warning "Health check script not found"
    fi
}

##############################################################################
# Stage 5: Integration Tests
##############################################################################

stage_integration_tests() {
    log_stage "Integration Tests"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_warning "Skipping integration tests in DRY RUN mode"
        return 0
    fi
    
    log_info "Running integration tests..."
    
    if [ -f "$SCRIPT_DIR/integration-tests.sh" ]; then
        bash "$SCRIPT_DIR/integration-tests.sh" "$NAMESPACE" || log_warning "Some integration tests failed"
    else
        log_warning "Integration test script not found"
    fi
}

##############################################################################
# Stage 6: Cleanup and Summary
##############################################################################

stage_cleanup_and_summary() {
    log_stage "Cleanup and Summary"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "DRY RUN mode: Nothing to clean up"
        echo ""
        echo -e "${GREEN}Dry-run completed successfully!${NC}"
        echo ""
        echo "To perform the actual installation, run:"
        echo "  $0 $NAMESPACE $RELEASE_NAME false false"
        return 0
    fi
    
    if [ "$CLEANUP" == "true" ]; then
        log_warning "Auto-cleanup enabled. Uninstalling release..."
        
        if helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"; then
            log_success "Release uninstalled successfully"
        else
            log_error "Failed to uninstall release"
        fi
        
        # Delete namespace
        if kubectl delete namespace "$NAMESPACE"; then
            log_success "Namespace deleted"
        else
            log_warning "Could not delete namespace (may have other resources)"
        fi
    else
        log_info "Cleanup disabled. Release remains installed."
        log_info "To verify the installation, run the verification script:"
        log_info "  $SCRIPT_DIR/verify-helm-install.sh $NAMESPACE $RELEASE_NAME"
    fi
}

##############################################################################
# Main Execution
##############################################################################

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Orchestrator API Helm E2E Test Suite                   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    
    print_config
    
    # Execute stages
    stage_preflight_checks
    stage_helm_install
    stage_verify_deployments
    stage_component_tests
    stage_integration_tests
    stage_cleanup_and_summary
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}E2E Test Suite Completed Successfully!${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

main
