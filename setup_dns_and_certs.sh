#!/bin/bash
# Script to set up DNS records and handle certificate issuance

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Step 1: Applying Terraform configuration with flexible SSL...${NC}"
terraform apply -var-file=secrets.tfvars -auto-approve

echo -e "${YELLOW}Step 2: Waiting for certificate issuance (5 minutes)...${NC}"
echo "During this time, Traefik will detect the new domains and request certificates."
echo "The flexible SSL setting in Cloudflare allows this process to work smoothly."

# Wait for 5 minutes
for i in {300..1}; do
    if [ $((i % 60)) -eq 0 ]; then
        echo -e "${YELLOW}$((i / 60)) minutes remaining...${NC}"
    fi
    sleep 1
done

echo -e "${YELLOW}Step 3: Updating Cloudflare SSL setting to full_strict...${NC}"
# Create a temporary file with the updated SSL setting
cat > ssl_update.tf << EOF
resource "cloudflare_zone_settings_override" "domain_settings" {
  zone_id = data.cloudflare_zone.domain.id
  
  settings {
    ssl = "full_strict"  # Change to full_strict after certificates are issued
    always_use_https = "on"
  }
}
EOF

# Apply the updated configuration
terraform apply -var-file=secrets.tfvars -auto-approve

echo -e "${GREEN}Setup complete!${NC}"
echo "Your DNS records have been created and certificates should be issued."
echo "You can now access your services at:"
echo "- https://dev-oci.${DOMAIN_NAME}"
echo "- https://registry.${DOMAIN_NAME}"
echo "- https://local.${DOMAIN_NAME}"
echo "- https://admin.pangolin.${DOMAIN_NAME}"
echo "- https://v2-11-1.dev-oci.${DOMAIN_NAME}"
echo "- https://v2.registry.${DOMAIN_NAME}"
echo "- https://alpine.local.${DOMAIN_NAME}"

echo -e "${YELLOW}Testing connectivity...${NC}"
# Test the main domains
for domain in "dev-oci" "registry" "local" "admin.pangolin" "v2-11-1.dev-oci" "v2.registry" "alpine.local"; do
    echo -n "Testing https://${domain}.${DOMAIN_NAME}... "
    if curl -s -o /dev/null -w "%{http_code}" "https://${domain}.${DOMAIN_NAME}" | grep -q "200\|301\|302"; then
        echo -e "${GREEN}Success!${NC}"
    else
        echo -e "${RED}Failed!${NC}"
    fi
done
