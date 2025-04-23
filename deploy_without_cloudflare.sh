#!/bin/bash
# Script to deploy the infrastructure without using Cloudflare

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== OCI Swarm Cluster - Deployment Script (Without Cloudflare) ===${NC}"
echo -e "${YELLOW}This script will deploy the infrastructure without using Cloudflare.${NC}"
echo -e "${YELLOW}You will need to manually configure Cloudflare DNS records after deployment.${NC}"
echo ""

# Check for required tools
for cmd in terraform; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd is required but not installed!${NC}"
        exit 1
    fi
done

# Check if secrets.tfvars exists
if [ ! -f "secrets.tfvars" ]; then
    echo -e "${RED}Error: secrets.tfvars file not found!${NC}"
    exit 1
fi

# Temporarily rename cloudflare.tf to disable it
if [ -f "cloudflare.tf" ]; then
    echo -e "${YELLOW}Temporarily disabling Cloudflare provider...${NC}"
    mv cloudflare.tf cloudflare.tf.disabled
fi

# Check if deploy_web_app is set to true in secrets.tfvars
DEPLOY_WEB_APP=$(grep deploy_web_app secrets.tfvars | cut -d '=' -f2 | tr -d ' ')
if [ "$DEPLOY_WEB_APP" != "true" ]; then
    echo -e "${YELLOW}Setting deploy_web_app to true in secrets.tfvars...${NC}"
    # Check if deploy_web_app exists in the file
    if grep -q "deploy_web_app" secrets.tfvars; then
        # Replace the existing line
        sed -i 's/deploy_web_app.*=.*/deploy_web_app = true # Web application will be deployed/g' secrets.tfvars
    else
        # Add the line if it doesn't exist
        echo "deploy_web_app = true # Web application will be deployed" >> secrets.tfvars
    fi
fi

# Run terraform init if .terraform directory doesn't exist
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Running terraform init...${NC}"
    terraform init

    # Check if terraform init was successful
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Terraform init failed!${NC}"
        exit 1
    fi
fi

# Run terraform apply to create the infrastructure
echo -e "${YELLOW}Running terraform apply to create the infrastructure...${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"
terraform apply -var-file=secrets.tfvars -auto-approve

# Check if terraform apply was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Terraform apply failed!${NC}"
    echo -e "${YELLOW}Please check the error messages above and fix any issues.${NC}"
    exit 1
fi

echo -e "${GREEN}Infrastructure deployed successfully!${NC}"

# Wait for the compute instances to be ready
echo -e "${YELLOW}Waiting for compute instances to be ready...${NC}"
echo -e "${YELLOW}This may take up to 5 minutes...${NC}"

# Wait for 2 minutes
for i in {1..4}; do
    echo -e "${YELLOW}Waiting... ($i/4)${NC}"
    sleep 30
done

# Get the compute instance IPs
echo -e "${YELLOW}Getting compute instance IPs...${NC}"
INSTANCE_IPS=$(terraform output -json | jq -r '.instance_public_ips.value[]' 2>/dev/null)

if [ -z "$INSTANCE_IPS" ]; then
    echo -e "${YELLOW}Warning: Could not get compute instance IPs from terraform output.${NC}"
    echo -e "${YELLOW}This may be because the output variable is not defined.${NC}"
    echo -e "${YELLOW}Continuing anyway...${NC}"
else
    echo -e "${GREEN}Compute instance IPs: ${INSTANCE_IPS}${NC}"

    # Try to ping the instances
    for ip in $INSTANCE_IPS; do
        echo -e "${YELLOW}Testing connectivity to ${ip}...${NC}"
        if ping -c 1 -W 2 $ip &> /dev/null; then
            echo -e "${GREEN}Successfully pinged ${ip}!${NC}"
        else
            echo -e "${YELLOW}Warning: Could not ping ${ip}.${NC}"
            echo -e "${YELLOW}This may be due to firewall settings or the instance is still starting up.${NC}"
        fi
    done
fi

# Wait for Traefik to be ready
echo -e "${YELLOW}Waiting for Traefik and other services to be ready...${NC}"
echo -e "${YELLOW}This may take up to 5 minutes...${NC}"

# Wait for 3 minutes
for i in {1..6}; do
    echo -e "${YELLOW}Waiting... ($i/6)${NC}"
    sleep 30
done

# Get the load balancer IP
LB_IP=$(terraform output -json | jq -r '.lb_ip_address.value' 2>/dev/null)

if [ -z "$LB_IP" ] || [ "$LB_IP" == "null" ]; then
    echo -e "${YELLOW}Warning: Could not get load balancer IP from terraform output.${NC}"
    echo -e "${YELLOW}This may be because the output variable is not defined.${NC}"
else
    echo -e "${GREEN}Load balancer IP: ${LB_IP}${NC}"
fi

# Restore cloudflare.tf
if [ -f "cloudflare.tf.disabled" ]; then
    echo -e "${YELLOW}Restoring Cloudflare provider...${NC}"
    mv cloudflare.tf.disabled cloudflare.tf
fi

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${YELLOW}You now need to manually configure Cloudflare DNS records:${NC}"
echo -e "${YELLOW}1. Log in to your Cloudflare dashboard${NC}"
echo -e "${YELLOW}2. Go to the DNS settings for your domain${NC}"
echo -e "${YELLOW}3. Add the following A records pointing to the load balancer IP (${LB_IP}):${NC}"
echo -e "${YELLOW}   - dev-oci.${DOMAIN_NAME}${NC}"
echo -e "${YELLOW}   - registry.${DOMAIN_NAME}${NC}"
echo -e "${YELLOW}   - local.${DOMAIN_NAME}${NC}"
echo -e "${YELLOW}   - v2-11-1.dev-oci.${DOMAIN_NAME}${NC}"
echo -e "${YELLOW}   - v2.registry.${DOMAIN_NAME}${NC}"
echo -e "${YELLOW}   - alpine.local.${DOMAIN_NAME}${NC}"
echo -e "${YELLOW}4. Add an A record for admin.pangolin.${DOMAIN_NAME} pointing to the first instance IP${NC}"
echo -e "${YELLOW}5. Set SSL/TLS mode to Full (Strict) in the Cloudflare dashboard${NC}"

echo -e "${YELLOW}To verify the deployment, run:${NC}"
echo -e "${GREEN}./tests/test_endpoints.sh${NC}"
echo -e "${GREEN}./tests/verify_deployment.sh${NC}"

echo -e "${BLUE}=== Deployment Complete ===${NC}"
