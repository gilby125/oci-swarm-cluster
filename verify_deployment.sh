#!/bin/bash
# Comprehensive verification script for OCI Swarm Cluster deployment
# This script checks all aspects of the deployment including:
# - DNS resolution
# - HTTP/HTTPS connectivity
# - Docker Swarm services
# - Cloudflare integration
# - Pangolin functionality

# Set colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
print_header() {
  echo -e "\n${BLUE}=======================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}=======================================${NC}"
}

# Print section
print_section() {
  echo -e "\n${YELLOW}--- $1 ---${NC}"
}

# Print success
print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

# Print failure
print_failure() {
  echo -e "${RED}✗ $1${NC}"
}

# Print info
print_info() {
  echo -e "${YELLOW}$1${NC}"
}

# Get Terraform outputs
get_terraform_outputs() {
  print_section "Getting Terraform outputs"
  
  DOMAIN=$(terraform output -raw domain_name 2>/dev/null || echo "")
  if [ -z "$DOMAIN" ]; then
    print_failure "Failed to get domain name from Terraform output"
    print_info "Please enter your domain name:"
    read -p "> " DOMAIN
  else
    print_success "Domain name: $DOMAIN"
  fi
  
  LB_IP=$(terraform output -raw lb_public_url 2>/dev/null | sed 's|http://||g' || echo "")
  if [ -z "$LB_IP" ]; then
    print_failure "Failed to get load balancer IP from Terraform output"
    print_info "Please enter the load balancer IP:"
    read -p "> " LB_IP
  else
    print_success "Load balancer IP: $LB_IP"
  fi
  
  PANGOLIN_TOKEN=$(terraform output -raw pangolin_token 2>/dev/null || echo "")
  if [ -z "$PANGOLIN_TOKEN" ]; then
    print_info "Pangolin token not found in Terraform output (this is expected if it's sensitive)"
  else
    print_success "Pangolin token retrieved"
  fi
  
  DEPLOY_DATABASE=$(terraform output -raw deploy_database 2>/dev/null || echo "true")
  DEPLOY_WEB_APP=$(terraform output -raw deploy_web_app 2>/dev/null || echo "true")
  
  print_info "Database deployment: $DEPLOY_DATABASE"
  print_info "Web app deployment: $DEPLOY_WEB_APP"
}

# Test DNS resolution
test_dns() {
  local domain=$1
  
  if command -v dig &> /dev/null; then
    result=$(dig +short $domain)
    if [ -n "$result" ]; then
      print_success "DNS resolution for $domain: $result"
      return 0
    else
      print_failure "DNS resolution failed for $domain"
      return 1
    fi
  elif command -v nslookup &> /dev/null; then
    result=$(nslookup $domain | grep "Address" | tail -n1 | awk '{print $2}')
    if [ -n "$result" ]; then
      print_success "DNS resolution for $domain: $result"
      return 0
    else
      print_failure "DNS resolution failed for $domain"
      return 1
    fi
  else
    print_failure "Neither dig nor nslookup is available"
    return 1
  fi
}

# Test HTTP/HTTPS connectivity
test_http() {
  local url=$1
  local expected_status=${2:-200}
  local timeout=${3:-10}
  
  if command -v curl &> /dev/null; then
    result=$(curl -s -o /dev/null -w "%{http_code}" --max-time $timeout "$url")
    if [ "$result" = "$expected_status" ]; then
      print_success "HTTP connectivity to $url: $result"
      return 0
    else
      print_failure "HTTP connectivity to $url failed: Expected $expected_status, got $result"
      return 1
    fi
  elif command -v wget &> /dev/null; then
    if wget -q --spider --timeout=$timeout "$url"; then
      print_success "HTTP connectivity to $url successful"
      return 0
    else
      print_failure "HTTP connectivity to $url failed"
      return 1
    fi
  else
    print_failure "Neither curl nor wget is available"
    return 1
  fi
}

# Test SSH connectivity to compute instances
test_ssh() {
  local ip=$1
  local key_file=$2
  
  if [ -z "$key_file" ]; then
    print_info "No SSH key file provided, skipping SSH test"
    return 0
  fi
  
  if command -v ssh &> /dev/null; then
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$key_file" opc@$ip "echo SSH connection successful"; then
      print_success "SSH connectivity to $ip successful"
      return 0
    else
      print_failure "SSH connectivity to $ip failed"
      return 1
    fi
  else
    print_failure "SSH command not available"
    return 1
  fi
}

# Test Docker Swarm services
test_docker_services() {
  local ip=$1
  local key_file=$2
  
  if [ -z "$key_file" ]; then
    print_info "No SSH key file provided, skipping Docker services test"
    return 0
  fi
  
  if command -v ssh &> /dev/null; then
    print_info "Checking Docker Swarm services..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$key_file" opc@$ip "docker service ls"
    
    print_info "Checking Pangolin container..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$key_file" opc@$ip "docker ps -f name=pangolin"
    
    print_info "Checking Traefik container..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$key_file" opc@$ip "docker ps -f name=traefik"
    
    return 0
  else
    print_failure "SSH command not available"
    return 1
  fi
}

# Test Cloudflare integration
test_cloudflare() {
  local domain=$1
  
  print_info "Testing Cloudflare integration for $domain..."
  
  if command -v curl &> /dev/null; then
    # Check if the domain is using Cloudflare
    result=$(curl -s -I "https://$domain" | grep -i "server: cloudflare")
    if [ -n "$result" ]; then
      print_success "Domain $domain is using Cloudflare"
      return 0
    else
      print_failure "Domain $domain is not using Cloudflare"
      return 1
    fi
  else
    print_failure "Curl command not available"
    return 1
  fi
}

# Main function
main() {
  print_header "OCI Swarm Cluster Deployment Verification"
  
  # Get Terraform outputs
  get_terraform_outputs
  
  # Wait for DNS propagation
  print_section "Waiting for DNS propagation (30 seconds)"
  sleep 30
  
  # Test DNS resolution
  print_section "Testing DNS resolution"
  test_dns "dev-oci.${DOMAIN}"
  test_dns "registry.${DOMAIN}"
  test_dns "local.${DOMAIN}"
  
  # Test HTTP connectivity
  print_section "Testing HTTP connectivity"
  test_http "http://${LB_IP}" 200
  test_http "http://${LB_IP}/whoami" 200
  
  # Test HTTPS connectivity
  print_section "Testing HTTPS connectivity"
  test_http "https://dev-oci.${DOMAIN}" 200 30
  test_http "https://registry.${DOMAIN}/v2/" 200 30
  test_http "https://local.${DOMAIN}" 200 30
  
  # Test Cloudflare integration
  print_section "Testing Cloudflare integration"
  test_cloudflare "dev-oci.${DOMAIN}"
  
  # Ask for SSH key file
  print_section "SSH connectivity tests"
  print_info "Enter the path to your SSH private key file (leave empty to skip SSH tests):"
  read -p "> " SSH_KEY_FILE
  
  if [ -n "$SSH_KEY_FILE" ]; then
    # Get compute instance IPs
    print_info "Enter the IP address of the first compute instance:"
    read -p "> " INSTANCE_IP
    
    # Test SSH connectivity
    test_ssh "$INSTANCE_IP" "$SSH_KEY_FILE"
    
    # Test Docker services
    print_section "Testing Docker services"
    test_docker_services "$INSTANCE_IP" "$SSH_KEY_FILE"
  fi
  
  # Summary
  print_header "Verification Summary"
  echo -e "Domain: ${DOMAIN}"
  echo -e "Load Balancer IP: ${LB_IP}"
  echo -e "Portainer UI: https://dev-oci.${DOMAIN}"
  echo -e "Registry: https://registry.${DOMAIN}/v2/"
  echo -e "Local Proxy: https://local.${DOMAIN}"
  echo -e "Whoami: http://${LB_IP}/whoami"
  
  print_section "Troubleshooting Tips"
  echo -e "1. DNS propagation can take up to 24 hours"
  echo -e "2. Services may take a few minutes to start up"
  echo -e "3. Check Cloudflare configuration if DNS resolution fails"
  echo -e "4. SSH into the compute instances to check Docker logs:"
  echo -e "   - docker logs \$(docker ps -q -f name=pangolin)"
  echo -e "   - docker logs \$(docker ps -q -f name=traefik)"
  echo -e "5. Run this verification script again after waiting a few minutes"
}

# Run the main function
main
