#!/bin/bash
# Script to add hosts file entries to fix DNS issues

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Adding hosts file entries to fix DNS issues...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script must be run as root!${NC}"
    echo -e "${YELLOW}Please run: sudo ./fix_hosts.sh${NC}"
    exit 1
fi

# Add hosts file entries
echo -e "${YELLOW}Adding entries to /etc/hosts...${NC}"
echo "104.16.132.229 dash.cloudflare.com" >> /etc/hosts
echo "104.16.132.229 edge.adobedc.net" >> /etc/hosts

echo -e "${GREEN}Hosts file entries added!${NC}"
echo -e "${YELLOW}Please clear your browser cache and cookies, then try accessing the Cloudflare dashboard again.${NC}"
