#!/bin/bash

# Helm Chart Validation Script for Azure Deployment
# This script validates the Helm chart before deploying to Azure AKS

set -e

CHART_DIR="."
NAMESPACE=${1:-thinklabs-orchestrator}
VALUES_FILE=${2:-values-dev.yaml}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Helm Chart Validation ===${NC}\n"

# 1. Check Helm is installed
echo -e "${YELLOW}[1/6] Checking Helm installation...${NC}"
if ! command -v helm &> /dev/null; then
  echo -e "${RED}✗ Helm is not installed${NC}"
  exit 1
fi
HELM_VERSION=$(helm version --short)
echo -e "${GREEN}✓ Helm installed: ${HELM_VERSION}${NC}\n"

# 2. Validate chart structure
echo -e "${YELLOW}[2/6] Validating chart structure...${NC}"
if [ ! -f "${CHART_DIR}/Chart.yaml" ]; then
  echo -e "${RED}✗ Chart.yaml not found${NC}"
  exit 1
fi
if [ ! -f "${CHART_DIR}/${VALUES_FILE}" ]; then
  echo -e "${RED}✗ ${VALUES_FILE} not found${NC}"
  exit 1
fi
if [ ! -d "${CHART_DIR}/templates" ]; then
  echo -e "${RED}✗ templates directory not found${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Chart structure is valid${NC}\n"

# 3. Lint the chart
echo -e "${YELLOW}[3/6] Linting chart...${NC}"
if helm lint ${CHART_DIR} --values ${CHART_DIR}/${VALUES_FILE}; then
  echo -e "${GREEN}✓ Helm lint passed${NC}\n"
else
  echo -e "${RED}✗ Helm lint failed${NC}"
  exit 1
fi

# 4. Validate template rendering
echo -e "${YELLOW}[4/6] Validating template rendering...${NC}"
if helm template thinklabs ${CHART_DIR} --values ${CHART_DIR}/${VALUES_FILE} > /tmp/rendered.yaml 2>&1; then
  echo -e "${GREEN}✓ Templates rendered successfully${NC}\n"
else
  echo -e "${RED}✗ Template rendering failed${NC}"
  cat /tmp/rendered.yaml
  exit 1
fi

# 5. Check for required values
echo -e "${YELLOW}[5/6] Checking required values...${NC}"
REQUIRED_KEYS=(
  "image.repository"
  "statusConsumerImage.repository"
  "api.ingress.hosts[0].host"
  "env.KAFKA_BROKERS"
  "env.REDIS_ADDR"
)

ALL_GOOD=true
for KEY in "${REQUIRED_KEYS[@]}"; do
  if grep -q "${KEY}" ${CHART_DIR}/${VALUES_FILE}; then
    echo -e "${GREEN}✓ Found: ${KEY}${NC}"
  else
    echo -e "${RED}✗ Missing: ${KEY}${NC}"
    ALL_GOOD=false
  fi
done

if [ "$ALL_GOOD" = false ]; then
  echo -e "\n${RED}✗ Some required values are missing${NC}"
  exit 1
fi
echo ""

# 6. Display rendered manifests (optional)
echo -e "${YELLOW}[6/6] Preview of rendered manifests...${NC}"
echo -e "${BLUE}Checking key resources:${NC}"

# Extract important info from rendered manifests
echo -e "\n${BLUE}Deployments:${NC}"
grep "kind: Deployment" /tmp/rendered.yaml -A 2 | grep "name:"

echo -e "\n${BLUE}Services:${NC}"
grep "kind: Service" /tmp/rendered.yaml -A 2 | grep "name:"

echo -e "\n${BLUE}Ingress:${NC}"
grep "kind: Ingress" /tmp/rendered.yaml -A 3 | grep "host:"

echo -e "\n${BLUE}Container Images:${NC}"
grep "image:" /tmp/rendered.yaml | sed 's/^[[:space:]]*//' | sort | uniq

# Summary
echo -e "\n${GREEN}✓ All validations passed!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Review Azure resources (Event Hubs, Redis, ACR)"
echo "2. Create secrets: ./create-secrets.sh ${NAMESPACE}"
echo "3. Install ingress controller (if not present)"
echo "4. Deploy: helm install thinklabs . -f ${VALUES_FILE} -n ${NAMESPACE}"
echo ""
echo -e "${BLUE}Tip: Use --dry-run to preview deployment:${NC}"
echo "helm install thinklabs . -f ${VALUES_FILE} -n ${NAMESPACE} --dry-run --debug"
