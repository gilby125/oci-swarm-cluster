#!/bin/bash
# Simplified deployment script for Docker Swarm

# Source the improved swarm initialization script
source /root/improved_swarm_init.sh

# Initialize the Docker Swarm
echo "Initializing Docker Swarm..."
IP_ADDRESS=$(hostname -I | awk '{print $1}')
init_swarm_manager "$IP_ADDRESS"

# Create overlay networks
echo "Creating overlay networks..."
create_overlay_networks

# Deploy the stack
echo "Deploying the stack..."
if [ -f "/root/docker-compose.yml" ]; then
    deploy_stack "/root/docker-compose.yml" "swarm"
else
    echo "Error: docker-compose.yml not found!"
    exit 1
fi

# Check stack status
echo "Checking stack status..."
check_stack_status "swarm"

echo "Deployment complete!"
