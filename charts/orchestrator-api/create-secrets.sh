#!/bin/bash

# Script to create Kubernetes secrets for in-cluster deployment
# Usage: ./create-secrets.sh <namespace>

NAMESPACE=${1:-thinklabs-orchestrator}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Creating Kubernetes secrets in namespace: ${NAMESPACE}${NC}"

# Create namespace if it doesn't exist
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# 1. Create Redis Secret (Optional - only for managed Azure Redis)
read -p "Are you using Azure Cache for Redis (managed)? (y/n): " USE_AZURE_REDIS
if [[ $USE_AZURE_REDIS == "y" || $USE_AZURE_REDIS == "Y" ]]; then
  read -p "Enter Redis access key: " REDIS_ACCESS_KEY
  if [ -z "$REDIS_ACCESS_KEY" ]; then
    echo -e "${RED}ERROR: Redis access key is required${NC}"
  else
    kubectl create secret generic redis-credentials \
      --from-literal=password="${REDIS_ACCESS_KEY}" \
      -n ${NAMESPACE} \
      --dry-run=client -o yaml | kubectl apply -f -
    
    echo -e "${GREEN}✓ Created redis-credentials secret${NC}"
  fi
else
  echo -e "${YELLOW}Skipped Redis secret (using in-cluster Redis)${NC}"
fi

# 2. Create Slack Webhook Secret (Optional)
read -p "Do you want to add Slack webhook URL? (y/n): " ADD_SLACK
if [[ $ADD_SLACK == "y" || $ADD_SLACK == "Y" ]]; then
  read -p "Enter Slack webhook URL: " SLACK_WEBHOOK
  if [ -n "$SLACK_WEBHOOK" ]; then
    kubectl create secret generic slack-webhook \
      --from-literal=webhook-url="${SLACK_WEBHOOK}" \
      -n ${NAMESPACE} \
      --dry-run=client -o yaml | kubectl apply -f -
    
    echo -e "${GREEN}✓ Created slack-webhook secret${NC}"
  fi
else
  echo -e "${YELLOW}Skipped Slack webhook secret${NC}"
fi

# 3. Create ACR Pull Secret (Optional)
read -p "Do you want to create ACR pull secret for private registry? (y/n): " CREATE_ACR
if [[ $CREATE_ACR == "y" || $CREATE_ACR == "Y" ]]; then
  read -p "Enter ACR registry URL (e.g., thinklabsacr.azurecr.io): " ACR_URL
  read -p "Enter ACR username: " ACR_USERNAME
  read -sp "Enter ACR password: " ACR_PASSWORD
  echo ""
  
  kubectl create secret docker-registry acr-secret \
    --docker-server=${ACR_URL} \
    --docker-username=${ACR_USERNAME} \
    --docker-password=${ACR_PASSWORD} \
    -n ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -
  
  echo -e "${GREEN}✓ Created acr-secret${NC}"
else
  echo -e "${YELLOW}Skipped ACR pull secret${NC}"
fi

# Verify secrets
echo -e "\n${YELLOW}Secrets created in namespace ${NAMESPACE}:${NC}"
kubectl get secrets -n ${NAMESPACE}

echo -e "\n${GREEN}✓ Secrets setup complete!${NC}"
