#!/bin/bash
# Script to fix Cloudflare SSL/TLS settings

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

echo -e "${YELLOW}Fixing Cloudflare SSL/TLS settings for domain: ${DOMAIN_NAME}${NC}"

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

# Get current SSL/TLS settings
echo -e "${YELLOW}Getting current SSL/TLS settings...${NC}"
SSL_SETTINGS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/ssl" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

CURRENT_SSL_MODE=$(echo $SSL_SETTINGS | jq -r '.result.value')

echo -e "${YELLOW}Current SSL/TLS mode: ${CURRENT_SSL_MODE}${NC}"

# Set SSL/TLS mode to Flexible to ensure browser compatibility
echo -e "${YELLOW}Setting SSL/TLS mode to Flexible...${NC}"
curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/ssl" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json" \
     --data '{"value":"flexible"}' > /dev/null

echo -e "${GREEN}SSL/TLS mode set to Flexible!${NC}"

# Get current SSL/TLS settings
echo -e "${YELLOW}Getting updated SSL/TLS settings...${NC}"
SSL_SETTINGS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/ssl" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

UPDATED_SSL_MODE=$(echo $SSL_SETTINGS | jq -r '.result.value')

echo -e "${GREEN}Updated SSL/TLS mode: ${UPDATED_SSL_MODE}${NC}"

# Get current Always Use HTTPS setting
echo -e "${YELLOW}Getting current Always Use HTTPS setting...${NC}"
HTTPS_SETTINGS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/always_use_https" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

CURRENT_HTTPS_MODE=$(echo $HTTPS_SETTINGS | jq -r '.result.value')

echo -e "${YELLOW}Current Always Use HTTPS setting: ${CURRENT_HTTPS_MODE}${NC}"

# Set Always Use HTTPS to off temporarily
echo -e "${YELLOW}Setting Always Use HTTPS to off temporarily...${NC}"
curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/always_use_https" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json" \
     --data '{"value":"off"}' > /dev/null

echo -e "${GREEN}Always Use HTTPS set to off!${NC}"

# Get updated Always Use HTTPS setting
echo -e "${YELLOW}Getting updated Always Use HTTPS setting...${NC}"
HTTPS_SETTINGS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/always_use_https" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

UPDATED_HTTPS_MODE=$(echo $HTTPS_SETTINGS | jq -r '.result.value')

echo -e "${GREEN}Updated Always Use HTTPS setting: ${UPDATED_HTTPS_MODE}${NC}"

echo -e "${GREEN}Cloudflare SSL/TLS settings fixed!${NC}"
echo -e "${YELLOW}Please clear your browser cache and try accessing the Cloudflare dashboard again.${NC}"
echo -e "${YELLOW}If you still experience issues, you can revert the changes by running this script again and setting the SSL/TLS mode back to ${CURRENT_SSL_MODE} and Always Use HTTPS back to ${CURRENT_HTTPS_MODE}.${NC}"
