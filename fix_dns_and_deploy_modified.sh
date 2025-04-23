#!/bin/bash
# Modified script to fix DNS issues and deploy the infrastructure
# This version skips the token verification step

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== OCI Swarm Cluster - DNS and Deployment Fix Script (Modified) ===${NC}"
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

# Skip token verification and proceed directly to getting the zone ID
echo -e "${YELLOW}Getting zone ID for ${DOMAIN_NAME}...${NC}"
ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME}" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

ZONE_SUCCESS=$(echo $ZONE_RESPONSE | jq -r '.success')
if [ "$ZONE_SUCCESS" != "true" ]; then
    echo -e "${RED}Error: Failed to get zone information!${NC}"
    echo -e "${RED}$(echo $ZONE_RESPONSE | jq -r '.errors[] | .message')${NC}"
    exit 1
fi

ZONE_ID=$(echo $ZONE_RESPONSE | jq -r '.result[0].id')
if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ]; then
    echo -e "${RED}Error: Could not find zone ID for ${DOMAIN_NAME}!${NC}"
    echo -e "${YELLOW}Please make sure the domain is correctly set up in Cloudflare.${NC}"
    exit 1
fi

echo -e "${GREEN}Found zone ID: ${ZONE_ID}${NC}"

# Get all DNS records
echo -e "${YELLOW}Getting all DNS records...${NC}"
DNS_RECORDS_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

DNS_RECORDS_SUCCESS=$(echo $DNS_RECORDS_RESPONSE | jq -r '.success')
if [ "$DNS_RECORDS_SUCCESS" != "true" ]; then
    echo -e "${RED}Error: Failed to get DNS records!${NC}"
    echo -e "${RED}$(echo $DNS_RECORDS_RESPONSE | jq -r '.errors[] | .message')${NC}"
    exit 1
fi

# Extract the A records
A_RECORD_IDS=$(echo $DNS_RECORDS_RESPONSE | jq -r '.result[] | select(.type == "A") | .id')
A_RECORD_COUNT=$(echo "$A_RECORD_IDS" | grep -v '^$' | wc -l)

echo -e "${GREEN}Found ${A_RECORD_COUNT} A records.${NC}"

# Delete all A records
if [ $A_RECORD_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Deleting all A records...${NC}"
    for id in $A_RECORD_IDS; do
        echo -e "${YELLOW}Deleting DNS record with ID: ${id}${NC}"
        DELETE_RESPONSE=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${id}" \
             -H "X-Auth-Email: ${CF_EMAIL}" \
             -H "Authorization: Bearer ${CF_API_TOKEN}" \
             -H "Content-Type: application/json")

        DELETE_SUCCESS=$(echo $DELETE_RESPONSE | jq -r '.success')
        if [ "$DELETE_SUCCESS" != "true" ]; then
            echo -e "${RED}Error: Failed to delete DNS record with ID: ${id}!${NC}"
            echo -e "${RED}$(echo $DELETE_RESPONSE | jq -r '.errors[] | .message')${NC}"
            # Continue with other records
        fi
    done
else
    echo -e "${GREEN}No A records to delete.${NC}"
fi

# Set Cloudflare SSL mode to flexible to allow certificate issuance
echo -e "${YELLOW}Setting Cloudflare SSL mode to flexible...${NC}"
SSL_RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/ssl" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json" \
     --data '{"value":"flexible"}')

SSL_SUCCESS=$(echo $SSL_RESPONSE | jq -r '.success')
if [ "$SSL_SUCCESS" != "true" ]; then
    echo -e "${RED}Error: Failed to set SSL mode to flexible!${NC}"
    echo -e "${RED}$(echo $SSL_RESPONSE | jq -r '.errors[] | .message')${NC}"
    exit 1
fi

echo -e "${GREEN}SSL mode set to flexible successfully!${NC}"

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

# Set Cloudflare SSL mode to full_strict
echo -e "${YELLOW}Setting Cloudflare SSL mode to full_strict...${NC}"
SSL_STRICT_RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/ssl" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json" \
     --data '{"value":"full_strict"}')

SSL_STRICT_SUCCESS=$(echo $SSL_STRICT_RESPONSE | jq -r '.success')
if [ "$SSL_STRICT_SUCCESS" != "true" ]; then
    echo -e "${RED}Warning: Failed to set SSL mode to full_strict!${NC}"
    echo -e "${RED}$(echo $SSL_STRICT_RESPONSE | jq -r '.errors[] | .message')${NC}"
    echo -e "${YELLOW}You may need to manually set the SSL mode to full_strict in the Cloudflare dashboard.${NC}"
else
    echo -e "${GREEN}SSL mode set to full_strict successfully!${NC}"
fi

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
