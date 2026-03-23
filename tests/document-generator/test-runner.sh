#!/bin/bash

##############################################################################
# Document Generator Module Test Runner
# Template for testing the document-generator service module
##############################################################################

set -e

# Get directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_ROOT="$(dirname "$SCRIPT_DIR")"
SHARED_DIR="$TESTS_ROOT/shared"

# Source shared utilities
source "$SHARED_DIR/test-utils.sh"

# Configuration
MODULE_NAME="document-generator"
NAMESPACE="${1:-thinklabs-document-generator}"
HELM_TESTS_DIR="$SCRIPT_DIR/helm"

export MODULE_NAME NAMESPACE

##############################################################################
# Main Execution
##############################################################################

main() {
    log_header "Document Generator Module Test Suite"
    
    echo ""
    echo "Module: $MODULE_NAME"
    echo "Namespace: $NAMESPACE"
    echo ""
    
    # Reset global counters
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
    TESTS_WARNED=0
    
    local test_failed=0
    
    # Run Helm verification tests
    if [ -d "$HELM_TESTS_DIR" ]; then
        log_section "Running Helm Verification Tests"
        
        if [ -x "$HELM_TESTS_DIR/verify-helm-install.sh" ]; then
            log_test "Running: verify-helm-install.sh"
            "$HELM_TESTS_DIR/verify-helm-install.sh" "$NAMESPACE" || test_failed=1
        else
            log_info "Helm tests not yet configured for $MODULE_NAME"
        fi
    else
        log_warning "Helm tests directory not found: $HELM_TESTS_DIR"
    fi
    
    # Note: Add unit tests when available
    log_info "Unit tests not yet configured for $MODULE_NAME"
    
    # Print summary
    print_test_summary
    
    return $test_failed
}

main "$@"
