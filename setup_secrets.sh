#!/bin/bash
# Script to help users set up their secrets.tfvars file

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}OCI Swarm Cluster - Secrets Setup${NC}"
echo "This script will help you create a secrets.tfvars file for your OCI Swarm Cluster deployment."
echo "The secrets.tfvars file contains sensitive information like API tokens and credentials."
echo "This file should NEVER be committed to version control."
echo ""

# Check if secrets.tfvars already exists
if [ -f "secrets.tfvars" ]; then
    echo -e "${YELLOW}A secrets.tfvars file already exists.${NC}"
    read -p "Do you want to overwrite it? (y/n): " overwrite
    if [ "$overwrite" != "y" ]; then
        echo "Exiting without changes."
        exit 0
    fi
fi

# Create the secrets.tfvars file
echo "# OCI authentication" > secrets.tfvars
read -p "Enter your tenancy OCID: " tenancy_ocid
echo "tenancy_ocid     = \"$tenancy_ocid\"" >> secrets.tfvars

read -p "Enter your fingerprint (leave blank if using CloudShell): " fingerprint
echo "fingerprint      = \"$fingerprint\"" >> secrets.tfvars

read -p "Enter your user OCID (leave blank if using CloudShell): " user_ocid
echo "user_ocid        = \"$user_ocid\"" >> secrets.tfvars

read -p "Enter your private key path (leave blank if using CloudShell): " private_key_path
echo "private_key_path = \"$private_key_path\"" >> secrets.tfvars

read -p "Enter your email address: " user_email
echo "user_email       = \"$user_email\"" >> secrets.tfvars

echo "" >> secrets.tfvars
echo "# Cloudflare and domain information" >> secrets.tfvars
read -p "Enter your Cloudflare account email: " cloudflare_email
echo "cloudflare_email       = \"$cloudflare_email\"" >> secrets.tfvars

read -p "Enter your Cloudflare API token: " cloudflare_api_token
echo "cloudflare_api_token   = \"$cloudflare_api_token\"" >> secrets.tfvars

echo "# Pangolin token will be automatically generated if not provided" >> secrets.tfvars
echo "# pangolin_token = \"\" # Uncomment and set this if you want to use a specific token" >> secrets.tfvars

read -p "Enter your domain name: " domain_name
echo "domain_name           = \"$domain_name\"" >> secrets.tfvars

echo "" >> secrets.tfvars
echo "# Deployment Options" >> secrets.tfvars
read -p "Do you want to deploy the database? (y/n, default: n): " deploy_db
if [ "$deploy_db" = "y" ]; then
    echo "deploy_database = true # Database will be deployed" >> secrets.tfvars
else
    echo "deploy_database = false # Database will not be deployed" >> secrets.tfvars
fi
echo "deploy_web_app = true # Web application will be deployed" >> secrets.tfvars

echo "" >> secrets.tfvars
echo "# Database configuration (only used if deploy_database = true)" >> secrets.tfvars
echo "autonomous_database_db_version = \"19c\" # Changed from 21c to 19c" >> secrets.tfvars

echo "" >> secrets.tfvars
echo "# Compute configuration" >> secrets.tfvars
echo "num_nodes = 2 # Reduced from 4 to 2 due to capacity constraints" >> secrets.tfvars

# Set proper permissions
chmod 600 secrets.tfvars

echo -e "${GREEN}secrets.tfvars file created successfully!${NC}"
echo "This file contains sensitive information and should not be committed to version control."
echo "The .gitignore file has been configured to exclude this file."
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review the secrets.tfvars file to ensure all information is correct"
echo "2. Run 'terraform init' to initialize the Terraform providers"
echo "3. Run './setup_dns_and_certs.sh' to set up DNS records and certificates"
