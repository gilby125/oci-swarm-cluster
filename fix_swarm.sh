#!/bin/bash
# Script to fix Docker Swarm initialization

set -e

# Get the IP addresses of all instances
echo "Getting IP addresses of all instances..."
INSTANCE_0_IP=$(terraform state show oci_core_instance.app_instance[0] | grep public_ip | head -1 | awk '{print $3}' | tr -d '"')
INSTANCE_1_IP=$(terraform state show oci_core_instance.app_instance[1] | grep public_ip | head -1 | awk '{print $3}' | tr -d '"')
INSTANCE_2_IP=$(terraform state show oci_core_instance.app_instance[2] | grep public_ip | head -1 | awk '{print $3}' | tr -d '"')
INSTANCE_3_IP=$(terraform state show oci_core_instance.app_instance[3] | grep public_ip | head -1 | awk '{print $3}' | tr -d '"')

echo "Instance 0 IP: $INSTANCE_0_IP"
echo "Instance 1 IP: $INSTANCE_1_IP"
echo "Instance 2 IP: $INSTANCE_2_IP"
echo "Instance 3 IP: $INSTANCE_3_IP"

# Check if Docker is installed on all instances
for IP in $INSTANCE_0_IP $INSTANCE_1_IP $INSTANCE_2_IP $INSTANCE_3_IP; do
    echo "Checking Docker on $IP..."
    if ! ssh -i id_rsa -o StrictHostKeyChecking=no opc@$IP "sudo docker version"; then
        echo "Docker not installed on $IP. Exiting."
        exit 1
    fi
done

# Open Docker Swarm ports on all instances
for IP in $INSTANCE_0_IP $INSTANCE_1_IP $INSTANCE_2_IP $INSTANCE_3_IP; do
    echo "Opening Docker Swarm ports on $IP..."
    ssh -i id_rsa -o StrictHostKeyChecking=no opc@$IP "sudo firewall-cmd --permanent --add-port=2377/tcp && sudo firewall-cmd --permanent --add-port=7946/tcp && sudo firewall-cmd --permanent --add-port=7946/udp && sudo firewall-cmd --permanent --add-port=4789/udp && sudo firewall-cmd --reload"
done

# Check if Docker Swarm is already initialized on the first instance
echo "Checking if Docker Swarm is already initialized on $INSTANCE_0_IP..."
if ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_IP "sudo docker node ls" &>/dev/null; then
    echo "Docker Swarm is already initialized on $INSTANCE_0_IP."
else
    echo "Initializing Docker Swarm on $INSTANCE_0_IP..."
    ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_IP "sudo docker swarm init --advertise-addr $INSTANCE_0_IP"
fi

# Get the worker join token
echo "Getting worker join token..."
JOIN_TOKEN=$(ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_IP "sudo docker swarm join-token worker -q")

if [ -z "$JOIN_TOKEN" ]; then
    echo "Failed to get join token. Exiting."
    exit 1
fi

echo "Join token: $JOIN_TOKEN"

# Join the other nodes to the swarm
for IP in $INSTANCE_1_IP $INSTANCE_2_IP $INSTANCE_3_IP; do
    echo "Checking if $IP is already part of the swarm..."
    if ssh -i id_rsa -o StrictHostKeyChecking=no opc@$IP "sudo docker info | grep 'Swarm: active'" &>/dev/null; then
        echo "$IP is already part of the swarm."
    else
        echo "Joining $IP to the swarm..."
        ssh -i id_rsa -o StrictHostKeyChecking=no opc@$IP "sudo docker swarm join --token $JOIN_TOKEN $INSTANCE_0_IP:2377 || echo 'Failed to join swarm, will try again later'"
    fi
done

# Verify the swarm status
echo "Verifying swarm status..."
ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_IP "sudo docker node ls"

# Create overlay networks if they don't exist
echo "Creating overlay networks..."
ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_IP "sudo docker network ls | grep -q lb_network || sudo docker network create --driver=overlay --attachable lb_network"
ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_IP "sudo docker network ls | grep -q agent_network || sudo docker network create --driver=overlay --attachable agent_network"

# Deploy the stack if docker-compose.yml exists
echo "Checking if docker-compose.yml exists..."
if ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_IP "sudo test -f /root/docker-compose.yml"; then
    echo "Deploying the stack..."
    ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_IP "sudo docker stack deploy -c /root/docker-compose.yml swarm"
else
    echo "docker-compose.yml not found on $INSTANCE_0_IP."
fi

echo "Docker Swarm initialization completed successfully."
