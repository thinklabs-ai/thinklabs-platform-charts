#!/bin/bash

##############################################################################
# Platform Charts Master Test Runner
# Orchestrates testing of all modules
##############################################################################

set -e

# Get directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$SCRIPT_DIR/shared"

# Source shared utilities
source "$SHARED_DIR/test-utils.sh"

# Configuration
MODULES_DIR="$SCRIPT_DIR"
RUN_MODULE="${1:-all}"

##############################################################################
# Helper Functions
##############################################################################

list_modules() {
    echo ""
    echo -e "${CYAN}Available modules:${NC}"
    echo ""
    
    for module_dir in "$MODULES_DIR"/*; do
        if [ -d "$module_dir" ] && [ -f "$module_dir/test-runner.sh" ]; then
            local module_name=$(basename "$module_dir")
            echo "  • $module_name"
        fi
    done
    echo ""
}

run_module_tests() {
    local module_name=$1
    local module_dir="$MODULES_DIR/$module_name"
    
    if [ ! -d "$module_dir" ]; then
        log_error "Module '$module_name' not found"
        return 1
    fi
    
    if [ ! -f "$module_dir/test-runner.sh" ]; then
        log_error "Test runner not found for module '$module_name'"
        return 1
    fi
    
    log_section "Testing Module: $module_name"
    
    # Run the module's test runner
    if "$module_dir/test-runner.sh"; then
        return 0
    else
        return 1
    fi
}

run_all_modules() {
    local failed_modules=()
    
    # Find all modules with test runners
    for module_dir in "$MODULES_DIR"/*; do
        if [ -d "$module_dir" ] && [ -f "$module_dir/test-runner.sh" ]; then
            local module_name=$(basename "$module_dir")
            
            # Skip shared and tests directories
            if [ "$module_name" != "shared" ] && [ "$module_name" != "tests" ]; then
                if ! run_module_tests "$module_name"; then
                    failed_modules+=("$module_name")
                fi
            fi
        fi
    done
    
    # Print final summary
    echo ""
    log_header "PLATFORM CHARTS - OVERALL TEST SUMMARY"
    echo ""
    
    local module_count=${#failed_modules[@]}
    if [ $module_count -eq 0 ]; then
        echo -e "${GREEN}✓ All modules passed testing!${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ The following modules failed:${NC}"
        for module in "${failed_modules[@]}"; do
            echo "  • $module"
        done
        echo ""
        return 1
    fi
}

##############################################################################
# Usage Information
##############################################################################

print_usage() {
    cat << 'EOF'

Platform Charts Test Runner
=============================

USAGE:
  ./all-tests.sh [MODULE|all|list|help]

OPTIONS:
  MODULE    Run tests for a specific module (e.g., orchestrator)
  all       Run tests for all modules (default)
  list      List available modules
  help      Show this help message

EXAMPLES:
  # Run all module tests
  ./all-tests.sh all
  ./all-tests.sh

  # Run tests for a specific module
  ./all-tests.sh orchestrator
  ./all-tests.sh document-generator

  # List available modules
  ./all-tests.sh list

EOF
}

##############################################################################
# Main Execution
##############################################################################

main() {
    log_header "Platform Charts Master Test Runner"
    
    case "$RUN_MODULE" in
        help|-h|--help)
            print_usage
            exit 0
            ;;
        list|-l|--list)
            list_modules
            exit 0
            ;;
        all|"")
            log_info "Running tests for all modules..."
            run_all_modules
            exit $?
            ;;
        *)
            log_info "Running tests for module: $RUN_MODULE"
            run_module_tests "$RUN_MODULE"
            exit $?
            ;;
    esac
}

main
