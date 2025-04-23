#!/bin/bash
# Script to check for local DNS issues

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

echo -e "${YELLOW}Checking DNS resolution for ${DOMAIN_NAME}...${NC}"

# Check DNS resolution using different DNS servers
echo -e "${YELLOW}Checking DNS resolution using system DNS...${NC}"
SYSTEM_DNS=$(dig +short $DOMAIN_NAME)
echo -e "${GREEN}System DNS resolution: ${SYSTEM_DNS}${NC}"

echo -e "${YELLOW}Checking DNS resolution using Google DNS (8.8.8.8)...${NC}"
GOOGLE_DNS=$(dig +short @8.8.8.8 $DOMAIN_NAME)
echo -e "${GREEN}Google DNS resolution: ${GOOGLE_DNS}${NC}"

echo -e "${YELLOW}Checking DNS resolution using Cloudflare DNS (1.1.1.1)...${NC}"
CLOUDFLARE_DNS=$(dig +short @1.1.1.1 $DOMAIN_NAME)
echo -e "${GREEN}Cloudflare DNS resolution: ${CLOUDFLARE_DNS}${NC}"

# Check if there are differences in DNS resolution
if [ "$SYSTEM_DNS" != "$GOOGLE_DNS" ] || [ "$SYSTEM_DNS" != "$CLOUDFLARE_DNS" ] || [ "$GOOGLE_DNS" != "$CLOUDFLARE_DNS" ]; then
    echo -e "${RED}Warning: DNS resolution differs between DNS servers!${NC}"
    echo -e "${YELLOW}This could indicate DNS propagation issues or local DNS caching issues.${NC}"
    echo -e "${YELLOW}Try flushing your DNS cache:${NC}"
    echo -e "   - Windows: Run 'ipconfig /flushdns' in Command Prompt as Administrator"
    echo -e "   - macOS: Run 'sudo killall -HUP mDNSResponder' in Terminal"
    echo -e "   - Linux: Run 'sudo systemd-resolve --flush-caches' or 'sudo service nscd restart' in Terminal"
else
    echo -e "${GREEN}DNS resolution is consistent across DNS servers.${NC}"
fi

# Check if /etc/hosts file has entries for the domain
echo -e "${YELLOW}Checking if /etc/hosts file has entries for ${DOMAIN_NAME}...${NC}"
HOSTS_ENTRIES=$(grep $DOMAIN_NAME /etc/hosts 2>/dev/null)
if [ -n "$HOSTS_ENTRIES" ]; then
    echo -e "${RED}Warning: Found entries for ${DOMAIN_NAME} in /etc/hosts file:${NC}"
    echo -e "${HOSTS_ENTRIES}"
    echo -e "${YELLOW}These entries could override DNS resolution. Consider removing them if they're causing issues.${NC}"
else
    echo -e "${GREEN}No entries found for ${DOMAIN_NAME} in /etc/hosts file.${NC}"
fi

# Check if there are any VPN or proxy settings that could affect DNS resolution
echo -e "${YELLOW}Checking for VPN or proxy settings...${NC}"
echo -e "${YELLOW}Please check if you're using a VPN or proxy that could affect DNS resolution.${NC}"
echo -e "${YELLOW}If you're using a VPN, try disconnecting from it and see if the issues persist.${NC}"
echo -e "${YELLOW}If you're using a proxy, try disabling it and see if the issues persist.${NC}"

echo -e "${GREEN}DNS check completed!${NC}"
echo -e "${YELLOW}If you still experience issues, please run the fix_cloudflare_proxy.sh and fix_cloudflare_ssl.sh scripts.${NC}"
