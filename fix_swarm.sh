#!/bin/bash
# Script to fix Docker Swarm setup

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if the private key exists
if [ ! -f ~/.ssh/oci_swarm_key.pem ]; then
    echo -e "${RED}Error: Private key not found!${NC}"
    echo -e "${YELLOW}Please run 'terraform output -raw generated_private_key_pem > ~/.ssh/oci_swarm_key.pem && chmod 600 ~/.ssh/oci_swarm_key.pem'${NC}"
    exit 1
fi

# Get the IP addresses of the instances
MANAGER_IP=$(terraform output -raw app_instance_public_ips | jq -r '.[0]')
WORKER_IP=$(terraform output -raw app_instance_public_ips | jq -r '.[1]')

if [ -z "$MANAGER_IP" ] || [ -z "$WORKER_IP" ]; then
    echo -e "${RED}Error: Could not get instance IP addresses from Terraform output!${NC}"
    exit 1
fi

echo -e "${YELLOW}Manager IP: ${MANAGER_IP}${NC}"
echo -e "${YELLOW}Worker IP: ${WORKER_IP}${NC}"

# Check if the manager is initialized
echo -e "${YELLOW}Checking if the manager is initialized...${NC}"
SWARM_STATUS=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "sudo docker info | grep Swarm | awk '{print \$2}'")

if [ "$SWARM_STATUS" != "active" ]; then
    echo -e "${YELLOW}Initializing Docker Swarm on the manager...${NC}"
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "sudo docker swarm init --advertise-addr ${MANAGER_IP}"
else
    echo -e "${GREEN}Docker Swarm is already initialized on the manager.${NC}"
fi

# Get the join token
echo -e "${YELLOW}Getting the join token...${NC}"
JOIN_TOKEN=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "sudo docker swarm join-token worker -q")

if [ -z "$JOIN_TOKEN" ]; then
    echo -e "${RED}Error: Could not get join token!${NC}"
    exit 1
fi

# Check if the worker is already in the swarm
echo -e "${YELLOW}Checking if the worker is already in the swarm...${NC}"
WORKER_STATUS=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${WORKER_IP} "sudo docker info | grep Swarm | awk '{print \$2}'")

if [ "$WORKER_STATUS" != "active" ]; then
    echo -e "${YELLOW}Joining the worker to the swarm...${NC}"
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${WORKER_IP} "sudo docker swarm join --token ${JOIN_TOKEN} ${MANAGER_IP}:2377"
else
    echo -e "${GREEN}Worker is already in the swarm.${NC}"
fi

# Create the required networks if they don't exist
echo -e "${YELLOW}Creating required Docker networks...${NC}"
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "
    if ! sudo docker network ls | grep -q 'lb_network'; then
        sudo docker network create --driver=overlay --attachable lb_network
        echo -e '${GREEN}Created lb_network${NC}'
    else
        echo -e '${GREEN}lb_network already exists${NC}'
    fi
    
    if ! sudo docker network ls | grep -q 'agent_network'; then
        sudo docker network create --driver=overlay --attachable agent_network
        echo -e '${GREEN}Created agent_network${NC}'
    else
        echo -e '${GREEN}agent_network already exists${NC}'
    fi
"

# Restart the Docker stack
echo -e "${YELLOW}Restarting the Docker stack...${NC}"
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "
    cd /root
    sudo docker stack rm swarm
    sleep 10
    sudo docker stack deploy -c docker-compose.yml swarm
"

echo -e "${GREEN}Docker Swarm setup fixed!${NC}"
echo -e "${YELLOW}Now run 'terraform apply -var-file=secrets.tfvars' to ensure Terraform state is in sync.${NC}"
