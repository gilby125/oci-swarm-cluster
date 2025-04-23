#!/bin/bash
# Script to fix duplicate DNS records in Cloudflare

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Extract Cloudflare credentials from secrets.tfvars
echo -e "${YELLOW}Extracting Cloudflare credentials from secrets.tfvars...${NC}"

if [ ! -f "secrets.tfvars" ]; then
    echo -e "${RED}Error: secrets.tfvars file not found!${NC}"
    exit 1
fi

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

echo -e "${YELLOW}Fixing duplicate DNS records for domain: ${DOMAIN_NAME}${NC}"

# Get the zone ID
echo -e "${YELLOW}Getting zone ID for ${DOMAIN_NAME}...${NC}"
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME}" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ]; then
    echo -e "${RED}Error: Could not find zone ID for ${DOMAIN_NAME}!${NC}"
    exit 1
fi

echo -e "${GREEN}Found zone ID: ${ZONE_ID}${NC}"

# Get all DNS records
echo -e "${YELLOW}Getting all DNS records...${NC}"
DNS_RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

# Extract the records
echo -e "${YELLOW}Analyzing DNS records...${NC}"
echo $DNS_RECORDS | jq -r '.result[] | "\(.id) \(.name) \(.type) \(.content) \(.proxied)"' > dns_records.txt

# Find duplicate records
echo -e "${YELLOW}Finding duplicate records...${NC}"
declare -A UNIQUE_RECORDS
declare -A RECORD_IDS
declare -A RECORD_PROXIED

# First pass: identify duplicates
while read -r id name type content proxied; do
    # Only process A records
    if [ "$type" != "A" ]; then
        continue
    fi
    
    key="${name}"
    
    if [[ -z "${UNIQUE_RECORDS[$key]}" ]]; then
        UNIQUE_RECORDS[$key]="${content}"
        RECORD_IDS[$key]="${id}"
        RECORD_PROXIED[$key]="${proxied}"
        echo -e "${GREEN}Keeping record: ${name} (${type}) -> ${content} (proxied: ${proxied})${NC}"
    else
        echo -e "${RED}Found duplicate record: ${name} (${type}) -> ${content} (proxied: ${proxied})${NC}"
        
        # If the current record is proxied and the existing one is not, keep this one instead
        if [ "${proxied}" == "true" ] && [ "${RECORD_PROXIED[$key]}" == "false" ]; then
            echo -e "${YELLOW}Replacing previous record with this one because it's proxied${NC}"
            
            # Delete the previous record
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_IDS[$key]}" \
                 -H "X-Auth-Email: ${CF_EMAIL}" \
                 -H "Authorization: Bearer ${CF_API_TOKEN}" \
                 -H "Content-Type: application/json" > /dev/null
            
            # Update our tracking
            UNIQUE_RECORDS[$key]="${content}"
            RECORD_IDS[$key]="${id}"
            RECORD_PROXIED[$key]="${proxied}"
        else
            # Delete the duplicate record
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${id}" \
                 -H "X-Auth-Email: ${CF_EMAIL}" \
                 -H "Authorization: Bearer ${CF_API_TOKEN}" \
                 -H "Content-Type: application/json" > /dev/null
        fi
    fi
done < dns_records.txt

# Clean up
rm dns_records.txt

echo -e "${GREEN}Duplicate DNS records cleanup completed!${NC}"

# Verify the cleanup
echo -e "${YELLOW}Verifying DNS records after cleanup...${NC}"
DNS_RECORDS_AFTER=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

echo -e "${YELLOW}Current DNS records:${NC}"
echo $DNS_RECORDS_AFTER | jq -r '.result[] | "\(.name) \(.type) \(.content) \(.proxied)"' | sort

echo -e "${GREEN}DNS cleanup completed!${NC}"
echo -e "${YELLOW}Now run 'terraform apply -var-file=secrets.tfvars' to ensure Terraform state is in sync.${NC}"
