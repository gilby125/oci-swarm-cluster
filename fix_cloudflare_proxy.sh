#!/bin/bash
# Script to fix Cloudflare proxy settings

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

echo -e "${YELLOW}Fixing Cloudflare proxy settings for domain: ${DOMAIN_NAME}${NC}"

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

# Process the records
echo -e "${YELLOW}Processing records...${NC}"
while read -r id name type content proxied; do
    # Only process A records
    if [ "$type" != "A" ]; then
        continue
    fi

    # Check if the record is for the main domain or a subdomain
    if [ "$name" == "$DOMAIN_NAME" ]; then
        # Main domain should be proxied
        if [ "$proxied" != "true" ]; then
            echo -e "${YELLOW}Updating main domain record to be proxied: ${name} -> ${content}${NC}"
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${id}" \
                 -H "X-Auth-Email: ${CF_EMAIL}" \
                 -H "Authorization: Bearer ${CF_API_TOKEN}" \
                 -H "Content-Type: application/json" \
                 --data "{\"type\":\"A\",\"name\":\"${name}\",\"content\":\"${content}\",\"proxied\":true}" > /dev/null
        else
            echo -e "${GREEN}Main domain record is already proxied: ${name} -> ${content}${NC}"
        fi
    else
        # Subdomains should be proxied unless they have "oci" in the comment
        if [[ "$content" == *"oci"* ]]; then
            # OCI records should not be proxied
            if [ "$proxied" != "false" ]; then
                echo -e "${YELLOW}Updating OCI record to not be proxied: ${name} -> ${content}${NC}"
                curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${id}" \
                     -H "X-Auth-Email: ${CF_EMAIL}" \
                     -H "Authorization: Bearer ${CF_API_TOKEN}" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"${name}\",\"content\":\"${content}\",\"proxied\":false}" > /dev/null
            else
                echo -e "${GREEN}OCI record is already not proxied: ${name} -> ${content}${NC}"
            fi
        else
            # Non-OCI records should be proxied
            if [ "$proxied" != "true" ]; then
                echo -e "${YELLOW}Updating record to be proxied: ${name} -> ${content}${NC}"
                curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${id}" \
                     -H "X-Auth-Email: ${CF_EMAIL}" \
                     -H "Authorization: Bearer ${CF_API_TOKEN}" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"${name}\",\"content\":\"${content}\",\"proxied\":true}" > /dev/null
            else
                echo -e "${GREEN}Record is already proxied: ${name} -> ${content}${NC}"
            fi
        fi
    fi
done <<< "$RECORDS"

echo -e "${GREEN}Cloudflare proxy settings fixed!${NC}"
