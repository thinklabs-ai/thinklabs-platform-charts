#!/bin/bash

##############################################################################
# Orchestrator Module Test Runner
# Orchestrates all tests for the orchestrator module (Helm + unit tests)
##############################################################################

set -e

# Get directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_ROOT="$(dirname "$SCRIPT_DIR")"
SHARED_DIR="$TESTS_ROOT/shared"

# Source shared utilities
source "$SHARED_DIR/test-utils.sh"

# Configuration
MODULE_NAME="orchestrator"
NAMESPACE="${1:-thinklabs-orchestrator}"
HELM_TESTS_DIR="$SCRIPT_DIR/helm"
UNIT_TESTS_DIR="$SCRIPT_DIR/tests"

export MODULE_NAME NAMESPACE

##############################################################################
# Main Execution
##############################################################################

main() {
    log_header "Orchestrator Module Test Suite"
    
    echo ""
    echo "Module: $MODULE_NAME"
    echo "Namespace: $NAMESPACE"
    echo "Helm Tests: $HELM_TESTS_DIR"
    echo "Unit Tests: $UNIT_TESTS_DIR"
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
        fi
    else
        log_warning "Helm tests directory not found: $HELM_TESTS_DIR"
    fi
    
    # Run unit tests
    if [ -d "$UNIT_TESTS_DIR" ]; then
        log_section "Running Unit Tests"
        
        if [ -x "$UNIT_TESTS_DIR/run_all_tests.sh" ]; then
            log_test "Running: run_all_tests.sh"
            "$UNIT_TESTS_DIR/run_all_tests.sh" || test_failed=1
        fi
    else
        log_warning "Unit tests directory not found: $UNIT_TESTS_DIR"
    fi
    
    # Print summary
    print_test_summary
    
    return $test_failed
}

main "$@"
