#!/bin/bash
# Script to check for browser cache issues

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Checking for browser cache issues...${NC}"

echo -e "${YELLOW}1. Clear your browser cache${NC}"
echo -e "   - Chrome: Press Ctrl+Shift+Delete, select 'Cached images and files', and click 'Clear data'"
echo -e "   - Firefox: Press Ctrl+Shift+Delete, select 'Cache', and click 'Clear Now'"
echo -e "   - Edge: Press Ctrl+Shift+Delete, select 'Cached images and files', and click 'Clear'"
echo -e "   - Safari: Press Command+Option+E"

echo -e "${YELLOW}2. Try accessing the Cloudflare dashboard in an incognito/private window${NC}"
echo -e "   - Chrome: Press Ctrl+Shift+N"
echo -e "   - Firefox: Press Ctrl+Shift+P"
echo -e "   - Edge: Press Ctrl+Shift+N"
echo -e "   - Safari: Press Command+Shift+N"

echo -e "${YELLOW}3. Try using a different browser${NC}"

echo -e "${YELLOW}4. Check your browser extensions${NC}"
echo -e "   - Disable any ad blockers, privacy extensions, or security extensions temporarily"

echo -e "${YELLOW}5. Check your network connection${NC}"
echo -e "   - Try using a different network connection (e.g., switch from Wi-Fi to mobile data)"

echo -e "${YELLOW}6. Check your DNS settings${NC}"
echo -e "   - Try using a different DNS server (e.g., switch to Google DNS: 8.8.8.8 and 8.8.4.4)"

echo -e "${GREEN}If you still experience issues after trying these steps, please run the fix_cloudflare_proxy.sh and fix_cloudflare_ssl.sh scripts.${NC}"
