#!/bin/bash
# Script to fix Docker Swarm initialization using private IPs

set -e

# Get the IP addresses of all instances
echo "Getting IP addresses of all instances..."
INSTANCE_0_PUBLIC_IP=$(terraform state show oci_core_instance.app_instance[0] | grep public_ip | head -1 | awk '{print $3}' | tr -d '"')
INSTANCE_0_PRIVATE_IP=$(ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_PUBLIC_IP "ip addr show | grep -A 2 'inet 10.0'" | grep inet | awk '{print $2}' | cut -d/ -f1)

echo "Instance 0 Public IP: $INSTANCE_0_PUBLIC_IP"
echo "Instance 0 Private IP: $INSTANCE_0_PRIVATE_IP"

# Reset the swarm on the first instance
echo "Resetting Docker Swarm on $INSTANCE_0_PUBLIC_IP..."
ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_PUBLIC_IP "sudo docker swarm leave --force || true"

# Initialize Docker Swarm on the first instance using the private IP
echo "Initializing Docker Swarm on $INSTANCE_0_PUBLIC_IP using private IP $INSTANCE_0_PRIVATE_IP..."
ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_PUBLIC_IP "sudo docker swarm init --advertise-addr $INSTANCE_0_PRIVATE_IP"

# Get the worker join token
echo "Getting worker join token..."
JOIN_TOKEN=$(ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_PUBLIC_IP "sudo docker swarm join-token worker -q")

if [ -z "$JOIN_TOKEN" ]; then
    echo "Failed to get join token. Exiting."
    exit 1
fi

echo "Join token: $JOIN_TOKEN"

# Get the IP addresses of the other instances
INSTANCE_1_PUBLIC_IP=$(terraform state show oci_core_instance.app_instance[1] | grep public_ip | head -1 | awk '{print $3}' | tr -d '"')
INSTANCE_2_PUBLIC_IP=$(terraform state show oci_core_instance.app_instance[2] | grep public_ip | head -1 | awk '{print $3}' | tr -d '"')
INSTANCE_3_PUBLIC_IP=$(terraform state show oci_core_instance.app_instance[3] | grep public_ip | head -1 | awk '{print $3}' | tr -d '"')

echo "Instance 1 Public IP: $INSTANCE_1_PUBLIC_IP"
echo "Instance 2 Public IP: $INSTANCE_2_PUBLIC_IP"
echo "Instance 3 Public IP: $INSTANCE_3_PUBLIC_IP"

# Reset the swarm on the other instances
for IP in $INSTANCE_1_PUBLIC_IP $INSTANCE_2_PUBLIC_IP $INSTANCE_3_PUBLIC_IP; do
    echo "Resetting Docker Swarm on $IP..."
    ssh -i id_rsa -o StrictHostKeyChecking=no opc@$IP "sudo docker swarm leave --force || true"
done

# Join the other nodes to the swarm
for IP in $INSTANCE_1_PUBLIC_IP $INSTANCE_2_PUBLIC_IP $INSTANCE_3_PUBLIC_IP; do
    echo "Joining $IP to the swarm..."
    ssh -i id_rsa -o StrictHostKeyChecking=no opc@$IP "sudo docker swarm join --token $JOIN_TOKEN $INSTANCE_0_PRIVATE_IP:2377 || echo 'Failed to join swarm, will try again later'"
done

# Verify the swarm status
echo "Verifying swarm status..."
ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_PUBLIC_IP "sudo docker node ls"

# Create overlay networks if they don't exist
echo "Creating overlay networks..."
ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_PUBLIC_IP "sudo docker network ls | grep -q lb_network || sudo docker network create --driver=overlay --attachable lb_network"
ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_PUBLIC_IP "sudo docker network ls | grep -q agent_network || sudo docker network create --driver=overlay --attachable agent_network"

# Deploy the stack if docker-compose.yml exists
echo "Checking if docker-compose.yml exists..."
if ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_PUBLIC_IP "sudo test -f /root/docker-compose.yml"; then
    echo "Deploying the stack..."
    ssh -i id_rsa -o StrictHostKeyChecking=no opc@$INSTANCE_0_PUBLIC_IP "sudo docker stack deploy -c /root/docker-compose.yml swarm"
else
    echo "docker-compose.yml not found on $INSTANCE_0_PUBLIC_IP."
fi

echo "Docker Swarm initialization completed successfully."
