#!/bin/bash
# Script to clean up stale DNS records before Terraform apply

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

# Define the subdomains we want to manage
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
for SUBDOMAIN in "${MANAGED_SUBDOMAINS[@]}"; do
    echo "Processing subdomain: $SUBDOMAIN"
    
    # Get all records for this subdomain
    SUBDOMAIN_RECORDS=$(echo "$RECORDS" | jq -r --arg name "$SUBDOMAIN" '.result[] | select(.name | startswith($name + ".")) | .id')
    
    # If there are multiple records, delete all but keep the most recent one
    if [ "$(echo "$SUBDOMAIN_RECORDS" | wc -l)" -gt 1 ]; then
        echo "Found multiple records for $SUBDOMAIN, cleaning up..."
        
        # Keep track of the most recent record
        MOST_RECENT_ID=""
        MOST_RECENT_DATE=""
        
        # Find the most recent record
        for RECORD_ID in $SUBDOMAIN_RECORDS; do
            RECORD_INFO=$(echo "$RECORDS" | jq -r --arg id "$RECORD_ID" '.result[] | select(.id == $id)')
            MODIFIED_DATE=$(echo "$RECORD_INFO" | jq -r '.modified_on')
            
            if [ -z "$MOST_RECENT_DATE" ] || [ "$MODIFIED_DATE" \> "$MOST_RECENT_DATE" ]; then
                MOST_RECENT_DATE="$MODIFIED_DATE"
                MOST_RECENT_ID="$RECORD_ID"
            fi
        done
        
        # Delete all records except the most recent one
        for RECORD_ID in $SUBDOMAIN_RECORDS; do
            if [ "$RECORD_ID" != "$MOST_RECENT_ID" ]; then
                echo "Deleting record ID: $RECORD_ID"
                DELETE_RESULT=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$RECORD_ID" \
                    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                    -H "Content-Type: application/json")
                
                if [ "$(echo "$DELETE_RESULT" | jq -r '.success')" == "true" ]; then
                    echo "Successfully deleted record ID: $RECORD_ID"
                else
                    echo "Failed to delete record ID: $RECORD_ID"
                    echo "Error: $(echo "$DELETE_RESULT" | jq -r '.errors[0].message')"
                fi
            fi
        done
    else
        echo "No duplicate records found for $SUBDOMAIN"
    fi
done

echo "DNS cleanup completed"
