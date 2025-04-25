#!/bin/bash
# Improved script to fix Docker Swarm setup with better error handling and retry logic

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source the improved swarm initialization script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/improved_swarm_init.sh"

echo -e "${BLUE}=== OCI Swarm Cluster - Improved Docker Swarm Fix Script ===${NC}"
echo -e "${YELLOW}This script will fix Docker Swarm setup with improved error handling and retry logic.${NC}"
echo ""

# Check if the private key exists
if [ ! -f ~/.ssh/oci_swarm_key.pem ]; then
    log_message "ERROR" "Private key not found!"
    log_message "INFO" "Please run 'terraform output -raw generated_private_key_pem > ~/.ssh/oci_swarm_key.pem && chmod 600 ~/.ssh/oci_swarm_key.pem'"
    exit 1
fi

# Get the IP addresses of the instances from endpoints.txt
if [ ! -f "endpoints.txt" ]; then
    log_message "ERROR" "endpoints.txt file not found! Run extract_endpoints.sh first."
    exit 1
fi

MANAGER_IP=$(grep "Compute Instance 0 IP:" endpoints.txt | cut -d ' ' -f5)
WORKER_IP=$(grep "Compute Instance 1 IP:" endpoints.txt | cut -d ' ' -f5)

if [ -z "$MANAGER_IP" ] || [ -z "$WORKER_IP" ]; then
    log_message "ERROR" "Could not get instance IP addresses from Terraform output!"
    exit 1
fi

log_message "INFO" "Manager IP: ${MANAGER_IP}"
log_message "INFO" "Worker IP: ${WORKER_IP}"

# Copy the improved scripts to the manager and worker nodes
log_message "INFO" "Copying improved scripts to the manager and worker nodes..."

# Create a temporary directory to hold the scripts
TEMP_DIR=$(mktemp -d)
cp "${SCRIPT_DIR}/scripts/improved_swarm_init.sh" "${TEMP_DIR}/"
cp "${SCRIPT_DIR}/scripts/improved_deploy.sh" "${TEMP_DIR}/"

# Copy scripts to manager
log_message "INFO" "Copying scripts to manager node..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem "${TEMP_DIR}/improved_swarm_init.sh" opc@${MANAGER_IP}:/tmp/
scp -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem "${TEMP_DIR}/improved_deploy.sh" opc@${MANAGER_IP}:/tmp/

# Copy scripts to worker
log_message "INFO" "Copying scripts to worker node..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem "${TEMP_DIR}/improved_swarm_init.sh" opc@${WORKER_IP}:/tmp/

# Move scripts to proper location on manager
log_message "INFO" "Moving scripts to proper location on manager..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "sudo mv /tmp/improved_swarm_init.sh /root/ && sudo mv /tmp/improved_deploy.sh /root/ && sudo chmod +x /root/improved_swarm_init.sh /root/improved_deploy.sh"

# Move scripts to proper location on worker
log_message "INFO" "Moving scripts to proper location on worker..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${WORKER_IP} "sudo mv /tmp/improved_swarm_init.sh /root/ && sudo chmod +x /root/improved_swarm_init.sh"

# Clean up temporary directory
rm -rf "${TEMP_DIR}"

# Initialize Docker Swarm on manager
log_message "INFO" "Initializing Docker Swarm on manager..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "sudo bash -c 'source /root/improved_swarm_init.sh && init_swarm_cluster manager ${MANAGER_IP}'"

# Get the join token
log_message "INFO" "Getting the join token..."
JOIN_TOKEN=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "sudo docker swarm join-token worker -q")

if [ -z "$JOIN_TOKEN" ]; then
    log_message "ERROR" "Could not get join token!"
    exit 1
fi

# Join worker to swarm
log_message "INFO" "Joining worker to swarm..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${WORKER_IP} "sudo bash -c 'source /root/improved_swarm_init.sh && init_swarm_cluster worker ${MANAGER_IP}'"

# Create overlay networks on manager
log_message "INFO" "Creating overlay networks on manager..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "sudo bash -c 'source /root/improved_swarm_init.sh && create_overlay_networks'"

# Deploy the stack
log_message "INFO" "Deploying the stack..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "sudo bash -c 'source /root/improved_deploy.sh && main_deploy'"

# Verify the deployment
log_message "INFO" "Verifying the deployment..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "sudo docker stack ls && sudo docker service ls"

log_message "INFO" "Docker Swarm setup fixed!"
log_message "INFO" "Now run 'terraform apply -var-file=secrets.tfvars' to ensure Terraform state is in sync."
