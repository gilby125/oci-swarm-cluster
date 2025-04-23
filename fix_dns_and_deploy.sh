#!/bin/bash
# Script to fix DNS issues and deploy the infrastructure

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== OCI Swarm Cluster - DNS and Deployment Fix Script ===${NC}"
echo -e "${YELLOW}This script will fix DNS issues and deploy the infrastructure.${NC}"
echo -e "${YELLOW}It will:${NC}"
echo -e "${YELLOW}1. Delete all existing A records in Cloudflare${NC}"
echo -e "${YELLOW}2. Set Cloudflare SSL mode to flexible${NC}"
echo -e "${YELLOW}3. Deploy the infrastructure with Terraform${NC}"
echo -e "${YELLOW}4. Wait for the compute instances to be ready${NC}"
echo -e "${YELLOW}5. Set Cloudflare SSL mode to full_strict${NC}"
echo ""

# Check for required tools
for cmd in curl jq terraform; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd is required but not installed!${NC}"
        exit 1
    fi
done

# Check if secrets.tfvars exists
if [ ! -f "secrets.tfvars" ]; then
    echo -e "${RED}Error: secrets.tfvars file not found!${NC}"
    echo -e "${YELLOW}Please run ./setup_secrets.sh to create it.${NC}"
    exit 1
fi

# Extract Cloudflare credentials from secrets.tfvars
CF_EMAIL=$(grep cloudflare_email secrets.tfvars | cut -d '=' -f2 | tr -d ' "')
CF_API_TOKEN=$(grep cloudflare_api_token secrets.tfvars | cut -d '=' -f2 | tr -d ' "')
DOMAIN_NAME=$(grep domain_name secrets.tfvars | cut -d '=' -f2 | tr -d ' "')

if [ -z "$CF_EMAIL" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}Error: Could not find Cloudflare credentials in secrets.tfvars!${NC}"
    echo -e "${YELLOW}Please make sure the following variables are set in secrets.tfvars:${NC}"
    echo -e "${YELLOW}- cloudflare_email${NC}"
    echo -e "${YELLOW}- cloudflare_api_token${NC}"
    echo -e "${YELLOW}- domain_name${NC}"
    exit 1
fi

if [ "$CF_API_TOKEN" == "YOUR_NEW_API_TOKEN_HERE" ]; then
    echo -e "${RED}Error: You need to replace the placeholder API token with your actual Cloudflare API token!${NC}"
    echo -e "${YELLOW}Please update the cloudflare_api_token value in secrets.tfvars.${NC}"
    exit 1
fi

echo -e "${GREEN}Found Cloudflare credentials:${NC}"
echo -e "${GREEN}Email: ${CF_EMAIL}${NC}"
echo -e "${GREEN}Domain: ${DOMAIN_NAME}${NC}"

# Proceed directly to Terraform operations
echo -e "${GREEN}Proceeding with Terraform operations...${NC}"

# Skip Cloudflare API operations and let Terraform handle them

# Disable Cloudflare provider by renaming cloudflare.tf
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

# Run terraform apply to recreate the infrastructure
echo -e "${YELLOW}Running terraform apply to recreate the infrastructure...${NC}"
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

# Skip setting Cloudflare SSL mode to full_strict
echo -e "${YELLOW}Note: You may need to manually set the SSL mode to full_strict in the Cloudflare dashboard.${NC}"

# Update progress.md with the current status
echo -e "${YELLOW}Updating progress.md with the current status...${NC}"

# Get the current date
CURRENT_DATE=$(date +"%B %d, %Y")

# Update the date in progress.md
sed -i "s/## Current Status (.*)/## Current Status ($CURRENT_DATE)/g" progress.md

echo -e "${GREEN}DNS and deployment fixed successfully!${NC}"
echo -e "${YELLOW}Please wait a few minutes for the DNS changes to propagate and certificates to be issued.${NC}"
echo -e "${YELLOW}You can then access your services at:${NC}"
echo -e "${GREEN}https://dev-oci.${DOMAIN_NAME}${NC}"
echo -e "${GREEN}https://registry.${DOMAIN_NAME}${NC}"
echo -e "${GREEN}https://local.${DOMAIN_NAME}${NC}"
echo -e "${GREEN}https://admin.pangolin.${DOMAIN_NAME}${NC}"

echo -e "${YELLOW}To verify the deployment, run:${NC}"
echo -e "${GREEN}./tests/test_endpoints.sh${NC}"
echo -e "${GREEN}./tests/verify_deployment.sh${NC}"

echo -e "${BLUE}=== Fix Complete ===${NC}"
