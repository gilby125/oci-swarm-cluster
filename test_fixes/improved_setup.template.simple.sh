#!/bin/bash
# Improved setup script for Docker Swarm with better worker node joining

# Source the improved swarm initialization script
source /root/improved_swarm_init.sh

# Install Docker
log_message "INFO" "Installing Docker..."
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker

# Install Docker Compose
log_message "INFO" "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Setup SSH keys for secure communication between nodes
log_message "INFO" "Setting up SSH keys..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Use the SSH key provided by Terraform
cp /home/opc/.ssh/authorized_keys ~/.ssh/id_rsa.pub
chmod 644 ~/.ssh/id_rsa.pub
# The private key is injected by Terraform
if [ -f "/home/opc/.ssh/id_rsa" ]; then
    cp /home/opc/.ssh/id_rsa ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
else
    log_message "WARN" "Private key not found in /home/opc/.ssh/id_rsa"
fi

# Create swarm.env file
log_message "INFO" "Creating swarm.env file..."
cat > /root/swarm.env << 'EOL'
# Docker Swarm Environment Variables
DEPLOY_ID=DEPLOY_ID_VALUE
REGION_ID=REGION_ID_VALUE
DOMAIN_NAME=DOMAIN_NAME_VALUE
PANGOLIN_TOKEN=PANGOLIN_TOKEN_VALUE
PANGOLIN_ADMIN_PASSWORD=PANGOLIN_ADMIN_PASSWORD_VALUE
CLOUDFLARE_EMAIL=CLOUDFLARE_EMAIL_VALUE
CLOUDFLARE_API_TOKEN=CLOUDFLARE_API_TOKEN_VALUE
EOL

# Determine node type based on hostname
HOSTNAME=$(hostname)
log_message "INFO" "Hostname: $HOSTNAME"

# Get the manager node IP dynamically
# First try to get it from the swarm.env file
if [ -f "/root/swarm.env" ]; then
    source /root/swarm.env
    if [ -n "$MANAGER_IP" ]; then
        log_message "INFO" "Using manager IP from swarm.env: $MANAGER_IP"
    fi
fi

# If not found in swarm.env, try to resolve it from DNS
if [ -z "$MANAGER_IP" ]; then
    # Extract base hostname (remove node number)
    BASE_HOSTNAME=$(echo $HOSTNAME | sed 's/-[0-9]*$//')
    MANAGER_HOSTNAME="${BASE_HOSTNAME}-0"
    log_message "INFO" "Resolving manager hostname: $MANAGER_HOSTNAME"

    # Try to resolve the manager hostname
    MANAGER_IP=$(getent hosts $MANAGER_HOSTNAME | awk '{ print $1 }')

    if [ -n "$MANAGER_IP" ]; then
        log_message "INFO" "Resolved manager IP from hostname: $MANAGER_IP"
    else
        # Fallback to default IP if resolution fails
        MANAGER_IP="10.0.1.11"
        log_message "WARN" "Could not resolve manager hostname, using default IP: $MANAGER_IP"
    fi
fi

# Check if this is the manager node (node-0)
if [[ $HOSTNAME == *"-0" ]]; then
    log_message "INFO" "This is the manager node. Initializing swarm..."
    # Initialize the swarm on the manager node
    init_docker_swarm "manager"

    # Create required overlay networks
    create_overlay_networks

    # Deploy the stack
    log_message "INFO" "Deploying the stack..."
    if [ -f "/root/docker-compose.yml" ]; then
        deploy_stack "/root/docker-compose.yml" "swarm"
    else
        log_message "ERROR" "docker-compose.yml not found!"
    fi
else
    # This is a worker node, join the swarm
    log_message "INFO" "This is a worker node. Joining the swarm..."

    # Wait for manager to be ready
    log_message "INFO" "Waiting for manager node to be ready..."
    sleep 30

    # Get the join token from the manager with multiple retries
    log_message "INFO" "Getting join token from manager..."

    # Try multiple times with increasing delays
    max_attempts=5
    attempt=1
    delay=10

    while [ $attempt -le $max_attempts ]; do
        log_message "INFO" "Attempt $attempt/$max_attempts to get join token"

        # Try different SSH options
        TOKEN=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa opc@$MANAGER_IP "sudo docker swarm join-token worker -q" 2>/dev/null || echo "")

        if [ -n "$TOKEN" ]; then
            log_message "INFO" "Successfully got join token: $TOKEN"
            join_worker_node "$MANAGER_IP" "$TOKEN"
            break
        else
            # Try with root user
            TOKEN=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa root@$MANAGER_IP "docker swarm join-token worker -q" 2>/dev/null || echo "")

            if [ -n "$TOKEN" ]; then
                log_message "INFO" "Successfully got join token from root: $TOKEN"
                join_worker_node "$MANAGER_IP" "$TOKEN"
                break
            fi
        fi

        log_message "WARN" "Failed to get join token (Attempt $attempt/$max_attempts). Retrying in $delay seconds..."
        sleep $delay
        attempt=$((attempt+1))
        delay=$((delay*2))
    done

    # If all attempts failed, try a direct join
    if [ $attempt -gt $max_attempts ]; then
        log_message "ERROR" "All attempts to get join token failed. Trying direct join..."

        # Try to join directly using the Docker API
        log_message "INFO" "Joining swarm directly..."
        docker swarm join --advertise-addr $(hostname -I | awk '{print $1}') $MANAGER_IP:2377

        if [ $? -eq 0 ]; then
            log_message "INFO" "Successfully joined swarm directly"
        else
            log_message "ERROR" "Failed to join swarm directly. Manual intervention required."
        fi
    fi
fi

log_message "INFO" "Setup complete!"
