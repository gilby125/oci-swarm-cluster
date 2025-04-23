#!/bin/bash
# Script to fix SSL certificate generation

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if the private key exists
if [ ! -f ~/.ssh/oci_swarm_key.pem ]; then
    echo -e "${RED}Error: Private key not found!${NC}"
    echo -e "${YELLOW}Please run 'terraform output -raw generated_private_key_pem > ~/.ssh/oci_swarm_key.pem && chmod 600 ~/.ssh/oci_swarm_key.pem'${NC}"
    exit 1
fi

# Prompt for the manager IP
read -p "Enter the manager IP address: " MANAGER_IP

if [ -z "$MANAGER_IP" ]; then
    echo -e "${RED}Error: Manager IP address is required!${NC}"
    exit 1
fi

# Prompt for Cloudflare credentials
read -p "Enter your Cloudflare email: " CF_EMAIL
read -p "Enter your Cloudflare API token: " CF_API_TOKEN
read -p "Enter your domain name: " DOMAIN_NAME

if [ -z "$CF_EMAIL" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}Error: Missing required credentials!${NC}"
    exit 1
fi

echo -e "${YELLOW}Fixing SSL certificate generation for domain: ${DOMAIN_NAME}${NC}"

# Create a temporary file with the updated Traefik configuration
cat > traefik_dynamic_conf.toml << EOF
# Dynamic configuration for Traefik

[http.middlewares]
  [http.middlewares.secure-headers.headers]
    browserXssFilter = true
    contentTypeNosniff = true
    frameDeny = false
    sslRedirect = true
    hostsProxyHeaders = ["X-Forwarded-Host"]
    stsIncludeSubdomains = true
    stsPreload = true
    stsSeconds = 31536000
    customFrameOptionsValue = "SAMEORIGIN"
    # More permissive Content Security Policy that allows external resources
    contentSecurityPolicy = "default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; img-src * data: blob:; style-src * 'unsafe-inline'; script-src * 'unsafe-inline' 'unsafe-eval'; connect-src * 'unsafe-inline'; font-src * data:; object-src 'none'; media-src *; frame-src *; worker-src *; frame-ancestors *; form-action *; upgrade-insecure-requests;"

  [http.middlewares.compress.compress]
    excludedContentTypes = ["text/event-stream"]

  [http.middlewares.rate-limit.rateLimit]
    average = 100
    burst = 50

[tls.options]
  [tls.options.default]
    minVersion = "VersionTLS12"
    sniStrict = true
    cipherSuites = [
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
      "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
    ]
EOF

# Copy the updated Traefik configuration to the manager
echo -e "${YELLOW}Copying the updated Traefik configuration to the manager...${NC}"
scp -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem traefik_dynamic_conf.toml opc@${MANAGER_IP}:/tmp/traefik_dynamic_conf.toml

# Update the Traefik configuration and restart the container
echo -e "${YELLOW}Updating the Traefik configuration and restarting the container...${NC}"
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "
    sudo mv /tmp/traefik_dynamic_conf.toml /root/traefik_dynamic_conf.toml
    sudo chmod 644 /root/traefik_dynamic_conf.toml
    
    # Delete the acme.json file to force certificate regeneration
    sudo docker exec \$(sudo docker ps -q -f name=traefik) rm -f /data/acme.json
    
    # Restart the Traefik container
    sudo docker service update --force swarm_traefik
"

# Wait for the Traefik container to restart
echo -e "${YELLOW}Waiting for the Traefik container to restart (30 seconds)...${NC}"
sleep 30

# Check the Traefik logs for certificate requests
echo -e "${YELLOW}Checking the Traefik logs for certificate requests...${NC}"
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "
    sudo docker logs \$(sudo docker ps -q -f name=traefik) 2>&1 | grep -i 'certificate\|acme\|letsencrypt\|cloudflare'
"

echo -e "${GREEN}SSL certificate fix completed!${NC}"
echo -e "${YELLOW}It may take a few minutes for the certificates to be issued.${NC}"
echo -e "${YELLOW}You can check the status by running:${NC}"
echo -e "${YELLOW}ssh -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} \"sudo docker logs \\\$(sudo docker ps -q -f name=traefik) 2>&1 | grep -i 'certificate'\"${NC}"
