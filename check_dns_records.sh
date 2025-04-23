#!/bin/bash
# Script to check for DNS records with the same name

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

echo -e "${YELLOW}Checking DNS records for domain: ${DOMAIN_NAME}${NC}"

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

# Find duplicate A records
echo -e "${YELLOW}Finding duplicate A records...${NC}"
echo -e "${YELLOW}Format: NAME (TYPE) -> CONTENT (PROXIED) [RECORD_ID]${NC}"

# Create a temporary file with only A records
grep " A " dns_records.txt > a_records.txt

# Find duplicate A records by name
cut -d ' ' -f 2 a_records.txt | sort | uniq -c | sort -nr | while read count name; do
    if [ "$count" -gt 1 ]; then
        echo -e "${RED}Found $count A records with the name: $name${NC}"
        grep " $name " a_records.txt | while read id name type content proxied; do
            echo -e "${YELLOW}  $name ($type) -> $content (proxied: $proxied) [$id]${NC}"
        done
        echo ""
    fi
done

# Also check for records with the same name but different types
echo -e "${YELLOW}\nAll DNS records by name:${NC}"
echo -e "${YELLOW}Format: COUNT NAME${NC}"
cut -d ' ' -f 2 dns_records.txt | sort | uniq -c | sort -nr | head -n 10

# Show all A records for reference
echo -e "${YELLOW}\nAll A records:${NC}"
echo -e "${YELLOW}Format: NAME -> CONTENT (PROXIED)${NC}"
while read id name type content proxied; do
    echo -e "${GREEN}  $name -> $content (proxied: $proxied)${NC}"
done < a_records.txt

# Clean up
rm dns_records.txt a_records.txt

echo -e "${GREEN}DNS records check completed!${NC}"
