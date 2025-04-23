#!/bin/bash
# Test script to verify that all endpoints work after Terraform apply has completed
# This script checks DNS resolution and HTTP/HTTPS connectivity to the various services

# Set colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check if secrets.tfvars exists
if [ ! -f "../secrets.tfvars" ] && [ ! -f "./secrets.tfvars" ]; then
    echo -e "${RED}Error: secrets.tfvars file not found!${NC}"
    echo -e "${YELLOW}Please create a secrets.tfvars file using the setup_secrets.sh script.${NC}"
    echo -e "${YELLOW}Continuing with default values, but tests may fail.${NC}"
    SECRETS_FILE_EXISTS=false
else
    SECRETS_FILE_EXISTS=true
    # Determine the path to secrets.tfvars
    if [ -f "../secrets.tfvars" ]; then
        SECRETS_FILE="../secrets.tfvars"
    else
        SECRETS_FILE="./secrets.tfvars"
    fi

    # Extract domain name from secrets.tfvars if possible
    if [ "$SECRETS_FILE_EXISTS" = true ]; then
        DOMAIN_FROM_SECRETS=$(grep domain_name "$SECRETS_FILE" | cut -d '=' -f2 | tr -d ' "')
    fi
fi

# Get the domain name from Terraform output or secrets.tfvars
DOMAIN=$(terraform output -raw domain_name 2>/dev/null || echo "${DOMAIN_FROM_SECRETS:-throughfire.net}")
echo -e "${YELLOW}Testing endpoints for domain: ${DOMAIN}${NC}"

# Get the load balancer IP from Terraform output
LB_IP=$(terraform output -raw lb_public_url 2>/dev/null | sed 's|http://||g' || echo "")
if [ -z "$LB_IP" ]; then
  echo -e "${RED}Failed to get load balancer IP from Terraform output${NC}"
  echo -e "${YELLOW}Trying to get it from OCI CLI...${NC}"
  LB_IP=$(oci lb load-balancer list --compartment-id $(terraform output -raw compartment_ocid 2>/dev/null) --query "data[0].ip-addresses[0].ip-address" --raw-output 2>/dev/null)
  if [ -z "$LB_IP" ]; then
    echo -e "${RED}Failed to get load balancer IP. Please enter it manually:${NC}"
    read -p "Load Balancer IP: " LB_IP
  fi
fi

echo -e "${YELLOW}Load Balancer IP: ${LB_IP}${NC}"

# Function to test DNS resolution
test_dns() {
  local domain=$1
  echo -e "\n${YELLOW}Testing DNS resolution for ${domain}...${NC}"

  # Try to resolve the domain using dig
  if command -v dig &> /dev/null; then
    dig +short $domain
    if [ $? -eq 0 ] && [ -n "$(dig +short $domain)" ]; then
      echo -e "${GREEN}DNS resolution successful for ${domain}${NC}"
      return 0
    else
      echo -e "${RED}DNS resolution failed for ${domain}${NC}"
      return 1
    fi
  # If dig is not available, try nslookup
  elif command -v nslookup &> /dev/null; then
    nslookup $domain
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}DNS resolution successful for ${domain}${NC}"
      return 0
    else
      echo -e "${RED}DNS resolution failed for ${domain}${NC}"
      return 1
    fi
  else
    echo -e "${RED}Neither dig nor nslookup is available. Cannot test DNS resolution.${NC}"
    return 1
  fi
}

# Function to test HTTP/HTTPS connectivity
test_http() {
  local url=$1
  local expected_status=$2
  local method=${3:-GET}
  local data=${4:-""}

  echo -e "\n${YELLOW}Testing HTTP connectivity to ${url}...${NC}"

  # Try to connect to the URL using curl
  if command -v curl &> /dev/null; then
    if [ "$method" = "POST" ]; then
      response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -d "$data" "$url")
    else
      response=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    fi

    if [ "$response" = "$expected_status" ]; then
      echo -e "${GREEN}HTTP connectivity successful for ${url} (Status: ${response})${NC}"
      return 0
    else
      echo -e "${RED}HTTP connectivity failed for ${url} (Expected: ${expected_status}, Got: ${response})${NC}"
      return 1
    fi
  # If curl is not available, try wget
  elif command -v wget &> /dev/null; then
    if wget -q --spider "$url"; then
      echo -e "${GREEN}HTTP connectivity successful for ${url}${NC}"
      return 0
    else
      echo -e "${RED}HTTP connectivity failed for ${url}${NC}"
      return 1
    fi
  else
    echo -e "${RED}Neither curl nor wget is available. Cannot test HTTP connectivity.${NC}"
    return 1
  fi
}

# Function to test HTTPS connectivity with certificate validation
test_https_cert() {
  local domain=$1

  echo -e "\n${YELLOW}Testing HTTPS certificate for ${domain}...${NC}"

  # Try to check the certificate using openssl
  if command -v openssl &> /dev/null; then
    echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -dates
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}HTTPS certificate is valid for ${domain}${NC}"
      return 0
    else
      echo -e "${RED}HTTPS certificate validation failed for ${domain}${NC}"
      return 1
    fi
  else
    echo -e "${RED}OpenSSL is not available. Cannot test HTTPS certificate.${NC}"
    return 1
  fi
}

# Wait for DNS propagation
echo -e "\n${YELLOW}Waiting for DNS propagation (30 seconds)...${NC}"
sleep 30

# Test DNS resolution for all subdomains
test_dns "dev-oci.${DOMAIN}"
test_dns "registry.${DOMAIN}"
test_dns "local.${DOMAIN}"

# Test HTTP connectivity to the load balancer
test_http "http://${LB_IP}" 200

# Test HTTP connectivity to the whoami endpoint
test_http "http://${LB_IP}/whoami" 200

# Test HTTPS connectivity to the Portainer UI
test_http "https://dev-oci.${DOMAIN}" 200

# Test HTTPS connectivity to the Registry
test_http "https://registry.${DOMAIN}/v2/" 200

# Test HTTPS connectivity to the Local Proxy
test_http "https://local.${DOMAIN}" 200

# Test HTTPS connectivity to the Pangolin admin interface
echo -e "\n${YELLOW}Testing HTTP connectivity to the Pangolin admin interface...${NC}"
echo -e "${YELLOW}Note: This will return a 401 Unauthorized if the admin interface is working correctly${NC}"
test_http "https://admin.pangolin.${DOMAIN}" 401

# Test HTTPS certificates
test_https_cert "dev-oci.${DOMAIN}"
test_https_cert "registry.${DOMAIN}"
test_https_cert "local.${DOMAIN}"

echo -e "\n${GREEN}All tests completed!${NC}"

# Summary
echo -e "\n${YELLOW}=== Test Summary ===${NC}"
echo -e "Load Balancer: http://${LB_IP}"
echo -e "Portainer UI: https://dev-oci.${DOMAIN}"
echo -e "Registry: https://registry.${DOMAIN}/v2/"
echo -e "Local Proxy: https://local.${DOMAIN}"
echo -e "Whoami: http://${LB_IP}/whoami"

echo -e "\n${YELLOW}Note: If any tests failed, it might be because:${NC}"
echo -e "1. DNS propagation is still in progress (can take up to 24 hours)"
echo -e "2. The services are still starting up (can take a few minutes)"
echo -e "3. The Cloudflare integration is not properly configured"
echo -e "4. The Pangolin service is not running correctly"

echo -e "\n${YELLOW}To troubleshoot:${NC}"
echo -e "1. Check the Terraform output for any errors"
echo -e "2. SSH into the compute instances and check the Docker logs:"
echo -e "   - docker logs \$(docker ps -q -f name=pangolin)"
echo -e "   - docker logs \$(docker ps -q -f name=traefik)"
echo -e "3. Verify your Cloudflare configuration"
echo -e "4. Run this test script again after waiting a few minutes"
