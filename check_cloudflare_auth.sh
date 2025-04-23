#!/bin/bash
# Script to check Cloudflare authentication

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

# Check if the API token is valid
echo -e "${YELLOW}Checking if the API token is valid...${NC}"
TOKEN_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

TOKEN_STATUS=$(echo $TOKEN_CHECK | jq -r '.success')

if [ "$TOKEN_STATUS" == "true" ]; then
    echo -e "${GREEN}API token is valid!${NC}"
    echo -e "${GREEN}$(echo $TOKEN_CHECK | jq -r '.result.message')${NC}"
else
    echo -e "${RED}API token is invalid!${NC}"
    echo -e "${RED}$(echo $TOKEN_CHECK | jq -r '.errors[0].message')${NC}"
    echo -e "${YELLOW}Please check your Cloudflare API token and try again.${NC}"
    echo -e "${YELLOW}You may need to generate a new API token with the correct permissions.${NC}"
    exit 1
fi

# Check if the user has access to the domain
echo -e "${YELLOW}Checking if the user has access to the domain...${NC}"
ZONE_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME}" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

ZONE_STATUS=$(echo $ZONE_CHECK | jq -r '.success')

if [ "$ZONE_STATUS" == "true" ]; then
    ZONE_ID=$(echo $ZONE_CHECK | jq -r '.result[0].id')
    if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ]; then
        echo -e "${RED}User does not have access to the domain!${NC}"
        echo -e "${YELLOW}Please check your Cloudflare account and make sure you have access to the domain.${NC}"
        exit 1
    else
        echo -e "${GREEN}User has access to the domain!${NC}"
        echo -e "${GREEN}Zone ID: ${ZONE_ID}${NC}"
    fi
else
    echo -e "${RED}Failed to check domain access!${NC}"
    echo -e "${RED}$(echo $ZONE_CHECK | jq -r '.errors[0].message')${NC}"
    echo -e "${YELLOW}Please check your Cloudflare account and make sure you have access to the domain.${NC}"
    exit 1
fi

# Check user details
echo -e "${YELLOW}Checking user details...${NC}"
USER_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user" \
     -H "X-Auth-Email: ${CF_EMAIL}" \
     -H "Authorization: Bearer ${CF_API_TOKEN}" \
     -H "Content-Type: application/json")

USER_STATUS=$(echo $USER_CHECK | jq -r '.success')

if [ "$USER_STATUS" == "true" ]; then
    USER_ID=$(echo $USER_CHECK | jq -r '.result.id')
    USER_EMAIL=$(echo $USER_CHECK | jq -r '.result.email')
    USER_NAME=$(echo $USER_CHECK | jq -r '.result.first_name')
    echo -e "${GREEN}User details retrieved successfully!${NC}"
    echo -e "${GREEN}User ID: ${USER_ID}${NC}"
    echo -e "${GREEN}User Email: ${USER_EMAIL}${NC}"
    echo -e "${GREEN}User Name: ${USER_NAME}${NC}"
else
    echo -e "${RED}Failed to retrieve user details!${NC}"
    echo -e "${RED}$(echo $USER_CHECK | jq -r '.errors[0].message')${NC}"
    echo -e "${YELLOW}Please check your Cloudflare account and make sure you have the correct permissions.${NC}"
    exit 1
fi

echo -e "${GREEN}Cloudflare authentication check completed!${NC}"
echo -e "${YELLOW}If you're still experiencing issues with the Cloudflare dashboard, please try the following:${NC}"
echo -e "${YELLOW}1. Log out of the Cloudflare dashboard and log back in${NC}"
echo -e "${YELLOW}2. Clear your browser cookies for the Cloudflare dashboard${NC}"
echo -e "${YELLOW}3. Try accessing the Cloudflare dashboard from a different browser or device${NC}"
echo -e "${YELLOW}4. Contact Cloudflare support if the issue persists${NC}"
