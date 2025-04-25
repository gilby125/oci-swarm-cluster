#!/bin/bash
# Improved Docker Swarm initialization script with better error handling and retry logic

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to log messages with timestamp
log_message() {
    local level=$1
    local message=$2
    local color=$NC
    
    case $level in
        "INFO") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "ERROR") color=$RED ;;
    esac
    
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $color$level$NC: $message"
}

# Function to retry a command
retry_command() {
    local cmd=$1
    local description=$2
    local max_attempts=${3:-3}
    local delay=${4:-10}
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_message "INFO" "Attempt $attempt/$max_attempts: $description"
        eval $cmd
        if [ $? -eq 0 ]; then
            log_message "INFO" "$description - Successful"
            return 0
        else
            log_message "WARN" "$description - Failed (Attempt $attempt/$max_attempts)"
            if [ $attempt -lt $max_attempts ]; then
                log_message "INFO" "Retrying in $delay seconds..."
                sleep $delay
            fi
            attempt=$((attempt+1))
        fi
    done
    
    log_message "ERROR" "$description - All attempts failed"
    return 1
}

# Function to check if Docker is running
check_docker() {
    log_message "INFO" "Checking if Docker is running..."
    if ! systemctl is-active --quiet docker; then
        log_message "WARN" "Docker is not running, attempting to start it..."
        systemctl start docker
        sleep 5
        if ! systemctl is-active --quiet docker; then
            log_message "ERROR" "Failed to start Docker"
            return 1
        fi
    fi
    log_message "INFO" "Docker is running"
    return 0
}

# Function to initialize Docker Swarm on manager node
init_swarm_manager() {
    local ip=$1
    
    # Check if already part of a swarm
    if docker info | grep -q "Swarm: active"; then
        log_message "INFO" "This node is already part of an active swarm"
        return 0
    fi
    
    log_message "INFO" "Initializing Docker Swarm on manager node with IP: $ip"
    retry_command "docker swarm init --advertise-addr $ip" "Swarm initialization" 3 10
    
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to initialize Docker Swarm"
        return 1
    fi
    
    # Wait for swarm to stabilize
    log_message "INFO" "Waiting for swarm to stabilize..."
    sleep 15
    
    # Verify swarm initialization
    if ! docker node ls &>/dev/null; then
        log_message "ERROR" "Swarm verification failed"
        return 1
    fi
    
    log_message "INFO" "Docker Swarm successfully initialized"
    return 0
}

# Function to create overlay networks
create_overlay_networks() {
    log_message "INFO" "Creating required overlay networks..."
    
    # Create lb_network if it doesn't exist
    if ! docker network ls | grep -q "lb_network"; then
        log_message "INFO" "Creating lb_network..."
        retry_command "docker network create --driver=overlay --attachable lb_network" "Create lb_network" 3 5
        if [ $? -ne 0 ]; then
            log_message "ERROR" "Failed to create lb_network"
            return 1
        fi
    else
        log_message "INFO" "lb_network already exists"
    fi
    
    log_message "INFO" "Overlay networks created successfully"
    return 0
}

# Function to get worker join token
get_worker_token() {
    log_message "INFO" "Getting worker join token..."
    local token=$(docker swarm join-token worker -q)
    if [ -z "$token" ]; then
        log_message "ERROR" "Failed to get worker join token"
        return 1
    fi
    echo "$token"
    return 0
}

# Function to get manager join token
get_manager_token() {
    log_message "INFO" "Getting manager join token..."
    local token=$(docker swarm join-token manager -q)
    if [ -z "$token" ]; then
        log_message "ERROR" "Failed to get manager join token"
        return 1
    fi
    echo "$token"
    return 0
}

# Function to join a worker node to the swarm
join_worker_node() {
    local manager_ip=$1
    local token=$2
    
    # Check if already part of a swarm
    if docker info | grep -q "Swarm: active"; then
        log_message "INFO" "This node is already part of an active swarm"
        return 0
    fi
    
    log_message "INFO" "Joining worker node to swarm..."
    retry_command "docker swarm join --token $token $manager_ip:2377" "Join worker to swarm" 3 10
    
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to join worker to swarm"
        return 1
    fi
    
    log_message "INFO" "Worker node successfully joined the swarm"
    return 0
}

# Function to join a manager node to the swarm
join_manager_node() {
    local manager_ip=$1
    local token=$2
    
    # Check if already part of a swarm
    if docker info | grep -q "Swarm: active"; then
        log_message "INFO" "This node is already part of an active swarm"
        return 0
    fi
    
    log_message "INFO" "Joining manager node to swarm..."
    retry_command "docker swarm join --token $token $manager_ip:2377" "Join manager to swarm" 3 10
    
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to join manager to swarm"
        return 1
    fi
    
    log_message "INFO" "Manager node successfully joined the swarm"
    return 0
}

# Function to set up environment variables
setup_environment_variables() {
    log_message "INFO" "Setting up environment variables..."
    
    # Check if environment variables are already set in .bashrc
    if grep -q "DOMAIN_NAME" /root/.bashrc && grep -q "PANGOLIN_TOKEN" /root/.bashrc && grep -q "CLOUDFLARE_EMAIL" /root/.bashrc && grep -q "CLOUDFLARE_API_TOKEN" /root/.bashrc; then
        log_message "INFO" "Environment variables are already set"
        return 0
    fi
    
    # Add environment variables to .bashrc
    cat << EOF >> /root/.bashrc
export DOMAIN_NAME=${domain_name}
export PANGOLIN_TOKEN=${pangolin_token}
export CLOUDFLARE_EMAIL=${cloudflare_email}
export CLOUDFLARE_API_TOKEN=${cloudflare_api_token}
EOF
    
    # Source the environment variables
    source /root/.bashrc
    
    log_message "INFO" "Environment variables set up successfully"
    return 0
}

# Function to create Traefik dynamic configuration
create_traefik_config() {
    log_message "INFO" "Creating Traefik dynamic configuration..."
    
    # Create log directory for Traefik
    mkdir -p /var/log/traefik
    chmod 755 /var/log/traefik
    
    # Create dynamic configuration for Traefik
    cat > /root/traefik_dynamic_conf.toml << EOF
[http.middlewares]
  [http.middlewares.secure-headers.headers]
    sslRedirect = true
    stsSeconds = 31536000
    stsIncludeSubdomains = true
    stsPreload = true
    forceSTSHeader = true
    frameDeny = true
    customFrameOptionsValue = "SAMEORIGIN"
    contentTypeNosniff = true
    browserXssFilter = true
    customBrowserXSSValue = "1; mode=block"
    contentSecurityPolicy = "default-src 'self'; frame-ancestors 'self'"
    referrerPolicy = "same-origin"
EOF
    
    log_message "INFO" "Traefik dynamic configuration created successfully"
    return 0
}

# Function to deploy a stack
deploy_stack() {
    local compose_file=$1
    local stack_name=$2
    
    log_message "INFO" "Deploying stack: $stack_name from file: $compose_file"
    
    # Check if the compose file exists
    if [ ! -f "$compose_file" ]; then
        log_message "ERROR" "Compose file not found: $compose_file"
        return 1
    fi
    
    # Set up environment variables
    setup_environment_variables
    
    # Create Traefik configuration
    create_traefik_config
    
    # Process environment variables in the compose file
    log_message "INFO" "Processing environment variables in compose file..."
    local processed_file="$compose_file.processed"
    envsubst < "$compose_file" > "$processed_file"
    
    # Deploy the stack
    log_message "INFO" "Deploying stack..."
    retry_command "docker stack deploy -c $processed_file $stack_name" "Deploy stack" 3 10
    
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to deploy stack"
        return 1
    fi
    
    log_message "INFO" "Stack deployed successfully"
    return 0
}

# Function to check stack status
check_stack_status() {
    local stack_name=$1
    
    log_message "INFO" "Checking status of stack: $stack_name"
    
    # Check if the stack exists
    if ! docker stack ls | grep -q "$stack_name"; then
        log_message "ERROR" "Stack not found: $stack_name"
        return 1
    fi
    
    # Wait for services to be created
    log_message "INFO" "Waiting for services to be created..."
    sleep 10
    
    # Check service status
    local services=$(docker stack services $stack_name --format "{{.Name}} {{.Replicas}}")
    log_message "INFO" "Services status:"
    echo "$services"
    
    # Check for services with 0 replicas
    if echo "$services" | grep -q "0/"; then
        log_message "WARN" "Some services have 0 replicas running. Attempting to fix..."
        
        # Get list of services with 0 replicas
        local zero_replicas=$(echo "$services" | grep "0/" | awk '{print $1}')
        
        # Try to update each service with 0 replicas
        for service in $zero_replicas; do
            log_message "INFO" "Attempting to fix service: $service"
            retry_command "docker service update --force $service" "Update service $service" 3 10
        done
        
        # Check service status again
        log_message "INFO" "Checking service status after fixes..."
        services=$(docker stack services $stack_name --format "{{.Name}} {{.Replicas}}")
        echo "$services"
        
        if echo "$services" | grep -q "0/"; then
            log_message "WARN" "Some services still have 0 replicas running"
        else
            log_message "INFO" "All services are now running"
        fi
    else
        log_message "INFO" "All services are running"
    fi
    
    return 0
}

# Main function to initialize a Docker Swarm cluster
init_swarm_cluster() {
    local node_type=$1
    local manager_ip=$2
    
    # Check Docker status
    check_docker
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Docker check failed, cannot proceed with swarm initialization"
        return 1
    fi
    
    # Initialize or join swarm based on node type
    case $node_type in
        "manager")
            init_swarm_manager "$manager_ip"
            if [ $? -ne 0 ]; then
                return 1
            fi
            
            create_overlay_networks
            if [ $? -ne 0 ]; then
                return 1
            fi
            ;;
            
        "worker")
            if [ -z "$manager_ip" ]; then
                log_message "ERROR" "Manager IP is required for worker nodes"
                return 1
            fi
            
            # Get join token from manager
            local token=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@$manager_ip "sudo docker swarm join-token worker -q")
            if [ -z "$token" ]; then
                log_message "ERROR" "Failed to get join token from manager"
                return 1
            fi
            
            join_worker_node "$manager_ip" "$token"
            if [ $? -ne 0 ]; then
                return 1
            fi
            ;;
            
        "secondary-manager")
            if [ -z "$manager_ip" ]; then
                log_message "ERROR" "Manager IP is required for secondary manager nodes"
                return 1
            fi
            
            # Get join token from manager
            local token=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@$manager_ip "sudo docker swarm join-token manager -q")
            if [ -z "$token" ]; then
                log_message "ERROR" "Failed to get join token from manager"
                return 1
            fi
            
            join_manager_node "$manager_ip" "$token"
            if [ $? -ne 0 ]; then
                return 1
            fi
            ;;
            
        *)
            log_message "ERROR" "Invalid node type: $node_type. Must be 'manager', 'worker', or 'secondary-manager'"
            return 1
            ;;
    esac
    
    log_message "INFO" "Swarm cluster initialization completed successfully"
    return 0
}

# Export functions for use in other scripts
export -f log_message
export -f retry_command
export -f check_docker
export -f init_swarm_manager
export -f create_overlay_networks
export -f get_worker_token
export -f get_manager_token
export -f join_worker_node
export -f join_manager_node
export -f setup_environment_variables
export -f create_traefik_config
export -f deploy_stack
export -f check_stack_status
export -f init_swarm_cluster
