#!/bin/bash
# Script to check SSL certificate status for each domain

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Extract domain name from secrets.tfvars
echo -e "${YELLOW}Extracting domain name from secrets.tfvars...${NC}"

if [ ! -f "secrets.tfvars" ]; then
    echo -e "${RED}Error: secrets.tfvars file not found!${NC}"
    exit 1
fi

DOMAIN_NAME=$(grep domain_name secrets.tfvars | cut -d '=' -f2 | tr -d ' "')

if [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}Error: Could not find domain name in secrets.tfvars!${NC}"
    exit 1
fi

echo -e "${GREEN}Found domain name: ${DOMAIN_NAME}${NC}"

# Define the subdomains to check
SUBDOMAINS=(
    "dev-oci"
    "v2-11-1.dev-oci"
    "registry"
    "v2.registry"
    "local"
    "alpine.local"
    "admin.pangolin"
)

# Check SSL certificate for each subdomain
echo -e "${YELLOW}Checking SSL certificates for each subdomain...${NC}"

for subdomain in "${SUBDOMAINS[@]}"; do
    echo -e "${YELLOW}Checking SSL certificate for ${subdomain}.${DOMAIN_NAME}...${NC}"
    
    # Use openssl to check the certificate
    echo | openssl s_client -servername "${subdomain}.${DOMAIN_NAME}" -connect "${subdomain}.${DOMAIN_NAME}:443" 2>/dev/null | openssl x509 -noout -dates -issuer -subject > cert_info.txt
    
    if [ $? -eq 0 ]; then
        # Extract certificate information
        ISSUER=$(grep "issuer" cert_info.txt | sed 's/issuer=//')
        SUBJECT=$(grep "subject" cert_info.txt | sed 's/subject=//')
        NOT_BEFORE=$(grep "notBefore" cert_info.txt | sed 's/notBefore=//')
        NOT_AFTER=$(grep "notAfter" cert_info.txt | sed 's/notAfter=//')
        
        echo -e "${GREEN}  Certificate found for ${subdomain}.${DOMAIN_NAME}${NC}"
        echo -e "${GREEN}  Issuer: ${ISSUER}${NC}"
        echo -e "${GREEN}  Subject: ${SUBJECT}${NC}"
        echo -e "${GREEN}  Valid from: ${NOT_BEFORE}${NC}"
        echo -e "${GREEN}  Valid until: ${NOT_AFTER}${NC}"
    else
        echo -e "${RED}  No valid certificate found for ${subdomain}.${DOMAIN_NAME}${NC}"
        echo -e "${RED}  This could be due to DNS resolution issues or certificate not being issued yet.${NC}"
    fi
    
    echo ""
done

# Clean up
rm -f cert_info.txt

echo -e "${GREEN}SSL certificate check completed!${NC}"
