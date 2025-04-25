#!/bin/bash
# Script to SSH into the compute instances and restart the Docker services

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the SSH key from Terraform output
echo -e "${YELLOW}Getting SSH key from Terraform output...${NC}"
terraform output -raw generated_private_key_pem > ~/.ssh/oci_swarm_key.pem
chmod 600 ~/.ssh/oci_swarm_key.pem

# Extract endpoints from endpoints.txt
if [ ! -f "endpoints.txt" ]; then
    echo -e "${RED}Error: endpoints.txt file not found! Run extract_endpoints.sh first.${NC}"
    exit 1
fi

# Get compute instance IPs from endpoints.txt
INSTANCE_0_IP=$(grep "Compute Instance 0 IP:" endpoints.txt | cut -d ' ' -f5)
INSTANCE_1_IP=$(grep "Compute Instance 1 IP:" endpoints.txt | cut -d ' ' -f5)
echo -e "${YELLOW}Compute Instance 0 IP: ${INSTANCE_0_IP}${NC}"
echo -e "${YELLOW}Compute Instance 1 IP: ${INSTANCE_1_IP}${NC}"

# Function to run a command on a remote instance
run_remote_command() {
    local ip=$1
    local command=$2
    local description=$3
    
    echo -e "\n${YELLOW}${description} on ${ip}...${NC}"
    ssh -i ~/.ssh/oci_swarm_key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 opc@$ip "$command"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to run command on ${ip}!${NC}"
        return 1
    fi
    return 0
}

# Check and restart Docker services on both instances
for ip in $INSTANCE_0_IP $INSTANCE_1_IP; do
    echo -e "\n${YELLOW}Connecting to ${ip}...${NC}"
    
    # Check if we can SSH into the instance
    ssh -i ~/.ssh/oci_swarm_key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 opc@$ip "echo SSH connection successful"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to SSH into ${ip}!${NC}"
        continue
    fi
    
    # Check Docker status
    run_remote_command $ip "sudo systemctl status docker | grep Active" "Checking Docker status"
    
    # Restart Docker if necessary
    run_remote_command $ip "sudo systemctl restart docker" "Restarting Docker"
    
    # Check Docker Swarm status
    run_remote_command $ip "sudo docker info | grep -A 5 'Swarm'" "Checking Docker Swarm status"
    
    # List running containers
    run_remote_command $ip "sudo docker ps" "Listing running containers"
    
    # Restart the Docker Swarm stack
    run_remote_command $ip "cd /home/opc && sudo docker stack rm swarm" "Removing Docker Swarm stack"
    
    # Wait for the stack to be removed
    echo -e "${YELLOW}Waiting for the stack to be removed...${NC}"
    sleep 10
    
    # Deploy the stack again
    run_remote_command $ip "cd /home/opc && sudo docker stack deploy -c docker-compose.yml swarm" "Deploying Docker Swarm stack"
    
    # Check if the stack is deployed
    run_remote_command $ip "sudo docker stack ls" "Checking Docker Swarm stack"
    
    # Check if the services are running
    run_remote_command $ip "sudo docker service ls" "Checking Docker services"
    
    # Check the logs of the Traefik service
    run_remote_command $ip "sudo docker service logs swarm_traefik --tail 20" "Checking Traefik logs"
    
    # Check the logs of the whoami service
    run_remote_command $ip "sudo docker service logs swarm_whoami --tail 20" "Checking whoami logs"
    
    # Check if the whoami endpoint is responding
    run_remote_command $ip "curl -I http://localhost/whoami" "Checking whoami endpoint"
done

echo -e "\n${GREEN}Docker services restarted!${NC}"
echo -e "${YELLOW}Wait a few minutes for the services to start up and the health checks to pass.${NC}"
echo -e "${YELLOW}Then try accessing the services again.${NC}"
