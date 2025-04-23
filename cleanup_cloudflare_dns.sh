#!/bin/bash
# Script to clean up duplicate DNS records in Cloudflare

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Prompt for Cloudflare credentials
read -p "Enter your Cloudflare email: " CF_EMAIL
read -p "Enter your Cloudflare API token: " CF_API_TOKEN
read -p "Enter your domain name: " DOMAIN_NAME

if [ -z "$CF_EMAIL" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}Error: Missing required credentials!${NC}"
    exit 1
fi

echo -e "${YELLOW}Cleaning up duplicate DNS records for domain: ${DOMAIN_NAME}${NC}"

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
RECORDS=$(echo $DNS_RECORDS | jq -r '.result[] | "\(.id) \(.name) \(.type) \(.content) \(.proxied)"')

# Create arrays to store unique records
declare -A UNIQUE_RECORDS
declare -A RECORD_IDS

# Process the records
echo -e "${YELLOW}Processing records...${NC}"
while read -r id name type content proxied; do
    # Only process A records
    if [ "$type" != "A" ]; then
        continue
    fi
    
    key="${name}"
    
    # If this is the first record for this name, keep it
    if [[ -z "${UNIQUE_RECORDS[$key]}" ]]; then
        UNIQUE_RECORDS[$key]="${content}"
        RECORD_IDS[$key]="${id}"
        echo -e "${GREEN}Keeping record: ${name} (${type}) -> ${content} (proxied: ${proxied})${NC}"
    else
        # This is a duplicate, delete it
        echo -e "${RED}Deleting duplicate record: ${name} (${type}) -> ${content} (proxied: ${proxied})${NC}"
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${id}" \
             -H "X-Auth-Email: ${CF_EMAIL}" \
             -H "Authorization: Bearer ${CF_API_TOKEN}" \
             -H "Content-Type: application/json" > /dev/null
    fi
done <<< "$RECORDS"

echo -e "${GREEN}DNS cleanup completed!${NC}"
echo -e "${YELLOW}Now run 'terraform apply -var-file=secrets.tfvars' to ensure Terraform state is in sync.${NC}"
