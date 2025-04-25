#!/bin/bash

# Script to fix Docker Swarm networks

# Set up error handling
set -e
trap 'echo "Error on line $LINENO. Exiting..."; exit 1' ERR

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Docker Swarm network fix...${NC}"

# SSH to the manager node and create the required networks
echo -e "${GREEN}Connecting to manager node to create required networks...${NC}"
ssh -i id_rsa -o StrictHostKeyChecking=no opc@149.130.209.161 << 'ENDSSH'
# Create the required networks if they don't exist
echo "Creating required Docker Swarm networks..."

# Create lb_network if it doesn't exist
if ! sudo docker network ls | grep -q "lb_network"; then
  echo "Creating lb_network..."
  sudo docker network create --driver overlay --attachable lb_network
else
  echo "lb_network already exists."
fi

# Create agent_network if it doesn't exist
if ! sudo docker network ls | grep -q "agent_network"; then
  echo "Creating agent_network..."
  sudo docker network create --driver overlay --attachable agent_network
else
  echo "agent_network already exists."
fi

# Create traefik-public if it doesn't exist
if ! sudo docker network ls | grep -q "traefik-public"; then
  echo "Creating traefik-public..."
  sudo docker network create --driver overlay --attachable traefik-public
else
  echo "traefik-public already exists."
fi

# List all networks to verify
echo "Listing all Docker networks:"
sudo docker network ls
ENDSSH

echo -e "${GREEN}Docker Swarm network fix completed.${NC}"
