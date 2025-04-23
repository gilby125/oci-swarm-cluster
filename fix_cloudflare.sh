#!/bin/bash
# Script to fix Cloudflare DNS records and SSL settings

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== OCI Swarm Cluster - Cloudflare Fix Script ===${NC}"
echo -e "${YELLOW}This script will fix Cloudflare DNS records and SSL settings.${NC}"
echo ""

# Check for required tools
for cmd in curl jq; do
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

# Extract Cloudflare credentials from secrets.tfvars
CF_EMAIL=$(grep cloudflare_email secrets.tfvars | cut -d '=' -f2 | tr -d ' "')
CF_API_TOKEN=$(grep cloudflare_api_token secrets.tfvars | cut -d '=' -f2 | tr -d ' "')
DOMAIN_NAME=$(grep domain_name secrets.tfvars | cut -d '=' -f2 | tr -d ' "')

if [ -z "$CF_EMAIL" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}Error: Could not find Cloudflare credentials in secrets.tfvars!${NC}"
    exit 1
fi

echo -e "${GREEN}Found Cloudflare credentials:${NC}"
echo -e "${GREEN}Email: ${CF_EMAIL}${NC}"
echo -e "${GREEN}Domain: ${DOMAIN_NAME}${NC}"

# Get the zone ID using the API Key method
echo -e "${YELLOW}Getting zone ID for ${DOMAIN_NAME}...${NC}"
ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME}" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

# Check if the request was successful
if [[ $ZONE_RESPONSE == *"\"success\":false"* ]]; then
    echo -e "${RED}Error: Failed to get zone information!${NC}"
    echo -e "${RED}Response: ${ZONE_RESPONSE}${NC}"
    
    # Try alternative method with X-Auth-Key
    echo -e "${YELLOW}Trying alternative method...${NC}"
    echo -e "${YELLOW}Please enter your Cloudflare Global API Key:${NC}"
    read -s CF_API_KEY
    
    ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME}" \
         -H "X-Auth-Email: ${CF_EMAIL}" \
         -H "X-Auth-Key: ${CF_API_KEY}" \
         -H "Content-Type: application/json")
    
    if [[ $ZONE_RESPONSE == *"\"success\":false"* ]]; then
        echo -e "${RED}Error: Failed to get zone information with alternative method!${NC}"
        echo -e "${RED}Response: ${ZONE_RESPONSE}${NC}"
        exit 1
    else
        echo -e "${GREEN}Successfully retrieved zone information with alternative method!${NC}"
        # Save the API Key for future use
        CF_USE_API_KEY=true
    fi
else
    CF_USE_API_KEY=false
    echo -e "${GREEN}Successfully retrieved zone information!${NC}"
fi

# Extract the zone ID
ZONE_ID=$(echo $ZONE_RESPONSE | jq -r '.result[0].id')
if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ]; then
    echo -e "${RED}Error: Could not find zone ID for ${DOMAIN_NAME}!${NC}"
    exit 1
fi

echo -e "${GREEN}Found zone ID: ${ZONE_ID}${NC}"

# Function to make Cloudflare API requests
cf_api_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [ "$CF_USE_API_KEY" = true ]; then
        curl -s -X $method "https://api.cloudflare.com/client/v4${endpoint}" \
             -H "X-Auth-Email: ${CF_EMAIL}" \
             -H "X-Auth-Key: ${CF_API_KEY}" \
             -H "Content-Type: application/json" \
             ${data:+--data "$data"}
    else
        curl -s -X $method "https://api.cloudflare.com/client/v4${endpoint}" \
             -H "X-Auth-Email: ${CF_EMAIL}" \
             -H "Authorization: Bearer ${CF_API_TOKEN}" \
             -H "Content-Type: application/json" \
             ${data:+--data "$data"}
    fi
}

# Get all DNS records
echo -e "${YELLOW}Getting all DNS records...${NC}"
DNS_RECORDS_RESPONSE=$(cf_api_request "GET" "/zones/${ZONE_ID}/dns_records")

# Check if the request was successful
if [[ $DNS_RECORDS_RESPONSE == *"\"success\":false"* ]]; then
    echo -e "${RED}Error: Failed to get DNS records!${NC}"
    echo -e "${RED}Response: ${DNS_RECORDS_RESPONSE}${NC}"
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
        DELETE_RESPONSE=$(cf_api_request "DELETE" "/zones/${ZONE_ID}/dns_records/${id}")
        
        if [[ $DELETE_RESPONSE == *"\"success\":false"* ]]; then
            echo -e "${RED}Error: Failed to delete DNS record with ID: ${id}!${NC}"
            echo -e "${RED}Response: ${DELETE_RESPONSE}${NC}"
        else
            echo -e "${GREEN}Successfully deleted DNS record with ID: ${id}${NC}"
        fi
    done
else
    echo -e "${GREEN}No A records to delete.${NC}"
fi

# Set Cloudflare SSL mode to flexible
echo -e "${YELLOW}Setting Cloudflare SSL mode to flexible...${NC}"
SSL_RESPONSE=$(cf_api_request "PATCH" "/zones/${ZONE_ID}/settings/ssl" '{"value":"flexible"}')

if [[ $SSL_RESPONSE == *"\"success\":false"* ]]; then
    echo -e "${RED}Error: Failed to set SSL mode to flexible!${NC}"
    echo -e "${RED}Response: ${SSL_RESPONSE}${NC}"
else
    echo -e "${GREEN}SSL mode set to flexible successfully!${NC}"
fi

echo -e "${GREEN}Cloudflare DNS records and SSL settings fixed successfully!${NC}"
echo -e "${YELLOW}Now you can run terraform apply to deploy the infrastructure:${NC}"
echo -e "${GREEN}terraform apply -var-file=secrets.tfvars -auto-approve${NC}"

echo -e "${BLUE}=== Fix Complete ===${NC}"
