#!/bin/bash

# Script to clean up duplicate DNS records in Cloudflare
# This script will delete records pointing to the old load balancer IP

# Configuration
CLOUDFLARE_API_TOKEN="eTFAqWnzgU2MZQWTc4XTK2NQPmS8wcoCmwBA6Vxn"
ZONE_ID="5bbda6484109053a1e33c5c0544fb266"
OLD_IP="64.181.208.149"

# Get all DNS records
echo "Fetching DNS records..."
DNS_RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json")

# Extract records with the old IP
echo "Finding records with old IP $OLD_IP..."
OLD_RECORDS=$(echo $DNS_RECORDS | jq -r ".result[] | select(.content == \"$OLD_IP\") | {id: .id, name: .name, content: .content}")

# Display records to be deleted
echo "The following records will be deleted:"
echo "$OLD_RECORDS" | jq -r '"\(.name) -> \(.content) (ID: \(.id))"'

# Confirm deletion
read -p "Do you want to delete these records? (y/n): " confirm
if [[ $confirm != "y" ]]; then
  echo "Operation cancelled."
  exit 0
fi

# Delete records
echo "Deleting records..."
echo "$OLD_RECORDS" | jq -r '.id' | while read record_id; do
  echo "Deleting record $record_id..."
  RESULT=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")
  
  SUCCESS=$(echo $RESULT | jq -r '.success')
  if [[ $SUCCESS == "true" ]]; then
    echo "Successfully deleted record $record_id"
  else
    ERROR=$(echo $RESULT | jq -r '.errors[0].message')
    echo "Failed to delete record $record_id: $ERROR"
  fi
done

echo "DNS cleanup completed."
