#!/bin/bash

##############################################################################
# Slack Webhook Connectivity Verification Script
# 
# This script verifies that the Kubernetes cluster can reach the Slack webhook URL.
# It tests DNS resolution, network connectivity, and webhook functionality.
#
# Usage:
#   # Run in a one-time pod
#   kubectl run -it --rm slack-verify --image=curlimages/curl --restart=Never -- \
#     bash -c "$(cat verify-slack-webhook.sh)"
#
#   # Or build a test pod and run manually
#   kubectl apply -f slack-webhook-test-pod.yaml
#   kubectl logs -f pod/slack-webhook-test -n orchestrator
##############################################################################

set -e

echo "=========================================="
echo "Slack Webhook Connectivity Verification"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL}"
if [ -z "$SLACK_WEBHOOK_URL" ]; then
    echo "Error: SLACK_WEBHOOK_URL environment variable not set"
    exit 1
fi
SLACK_TEST_MESSAGE="Test notification from Kubernetes cluster verification"

# Extract hostname from URL
SLACK_HOST=$(echo "$SLACK_WEBHOOK_URL" | sed -E 's|^https?://([^/]+).*|\1|')

echo "📋 Configuration:"
echo "   Webhook Host: $SLACK_HOST"
echo "   Webhook URL: $SLACK_WEBHOOK_URL"
echo ""

# Test 1: DNS Resolution
echo "🔍 Test 1: DNS Resolution"
if command -v nslookup &> /dev/null; then
    if nslookup "$SLACK_HOST" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ DNS resolution successful${NC}"
        nslookup "$SLACK_HOST" | grep -A 1 "Address"
    else
        echo -e "${RED}✗ DNS resolution failed${NC}"
        exit 1
    fi
elif command -v getent &> /dev/null; then
    if getent hosts "$SLACK_HOST" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ DNS resolution successful${NC}"
        getent hosts "$SLACK_HOST"
    else
        echo -e "${RED}✗ DNS resolution failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ DNS tools not available, skipping DNS test${NC}"
fi
echo ""

# Test 2: Network Connectivity to HTTPS Port
echo "🔌 Test 2: Network Connectivity (TLS/HTTPS)"
if timeout 10 bash -c "cat < /dev/null > /dev/tcp/$SLACK_HOST/443" 2>/dev/null; then
    echo -e "${GREEN}✓ Port 443 (HTTPS) is accessible${NC}"
else
    echo -e "${RED}✗ Cannot reach port 443 - check network policies and NSG rules${NC}"
    exit 1
fi
echo ""

# Test 3: HTTPS Request (with curl)
echo "🌐 Test 3: HTTPS Request to Slack Webhook"
if command -v curl &> /dev/null; then
    echo "   Sending test request to Slack webhook..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H 'Content-type: application/json' \
        --data "{\"text\":\"$SLACK_TEST_MESSAGE\"}" \
        "$SLACK_WEBHOOK_URL" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo -e "${GREEN}✓ Webhook request successful (HTTP $HTTP_CODE)${NC}"
        echo "   Response: $BODY"
    else
        echo -e "${RED}✗ Webhook request failed (HTTP $HTTP_CODE)${NC}"
        echo "   Response: $BODY"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ curl not available, skipping webhook test${NC}"
fi
echo ""

# Test 4: Check from running pod (if available)
echo "📦 Test 4: Running Pod Verification"
if command -v kubectl &> /dev/null; then
    echo "   Checking status-consumer pod environment..."
    POD=$(kubectl get pods -n orchestrator -l app=status-consumer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$POD" ]; then
        WEBHOOK_VAR=$(kubectl exec -n orchestrator "$POD" -- env | grep SLACK_WEBHOOK_URL || echo "NOT_SET")
        NOTIFY_VAR=$(kubectl exec -n orchestrator "$POD" -- env | grep SLACK_NOTIFY_STATUSES || echo "NOT_SET")
        
        echo -e "${GREEN}✓ Pod found: $POD${NC}"
        echo "   $WEBHOOK_VAR"
        echo "   $NOTIFY_VAR"
    else
        echo -e "${YELLOW}⚠ No status-consumer pod found in orchestrator namespace${NC}"
    fi
else
    echo -e "${YELLOW}⚠ kubectl not available, skipping pod environment check${NC}"
fi
echo ""

# Summary
echo "=========================================="
echo "✅ Slack Webhook Verification Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Deploy status-consumer to orchestrator namespace"
echo "2. Monitor logs: kubectl logs -f deployment/status-consumer -n orchestrator"
echo "3. Look for 'notifySlack called' entries to confirm notifications are being sent"
echo ""
