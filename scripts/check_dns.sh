#!/bin/bash
# Script to check for duplicate DNS records in Cloudflare

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first."
    exit 1
fi

# Check if required environment variables are set
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Error: CLOUDFLARE_API_TOKEN environment variable is not set."
    echo "Usage: CLOUDFLARE_API_TOKEN=your_token CLOUDFLARE_ZONE_ID=your_zone_id $0"
    exit 1
fi

if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
    echo "Error: CLOUDFLARE_ZONE_ID environment variable is not set."
    echo "Usage: CLOUDFLARE_API_TOKEN=your_token CLOUDFLARE_ZONE_ID=your_zone_id $0"
    exit 1
fi

# Define the subdomains we want to check
MANAGED_SUBDOMAINS=(
    "dev-oci"
    "local"
    "local-version"
    "registry"
    "registry-version"
    "portainer"
    "portainer-version"
    "admin-pangolin"
)

# Get all DNS records for the zone
echo "Fetching DNS records for zone ID: $CLOUDFLARE_ZONE_ID"
RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

# Check if the API call was successful
if [ "$(echo "$RECORDS" | jq -r '.success')" != "true" ]; then
    echo "Error fetching DNS records: $(echo "$RECORDS" | jq -r '.errors[0].message')"
    exit 1
fi

# Process each managed subdomain
echo "Checking for duplicate DNS records..."
echo "------------------------------------"
FOUND_DUPLICATES=false

for SUBDOMAIN in "${MANAGED_SUBDOMAINS[@]}"; do
    # Get all records for this subdomain
    SUBDOMAIN_RECORDS=$(echo "$RECORDS" | jq -r --arg name "$SUBDOMAIN" '.result[] | select(.name | startswith($name + ".")) | .id')
    RECORD_COUNT=$(echo "$SUBDOMAIN_RECORDS" | grep -v '^$' | wc -l)
    
    if [ "$RECORD_COUNT" -gt 1 ]; then
        FOUND_DUPLICATES=true
        echo "⚠️  Found $RECORD_COUNT records for $SUBDOMAIN - DUPLICATE DETECTED"
        
        # Show details for each record
        echo "$RECORDS" | jq -r --arg name "$SUBDOMAIN" '.result[] | select(.name | startswith($name + ".")) | "   - ID: \(.id), Content: \(.content), Type: \(.type), Proxied: \(.proxied)"'
    else
        if [ "$RECORD_COUNT" -eq 1 ]; then
            echo "✅ Found 1 record for $SUBDOMAIN - OK"
            echo "$RECORDS" | jq -r --arg name "$SUBDOMAIN" '.result[] | select(.name | startswith($name + ".")) | "   - Content: \(.content), Type: \(.type), Proxied: \(.proxied)"'
        else
            echo "❓ No records found for $SUBDOMAIN"
        fi
    fi
    echo ""
done

if [ "$FOUND_DUPLICATES" = true ]; then
    echo "⚠️  Duplicate DNS records detected!"
    echo "Run the cleanup script to fix this issue:"
    echo "  ./scripts/cleanup_dns.sh"
else
    echo "✅ No duplicate DNS records found."
fi
