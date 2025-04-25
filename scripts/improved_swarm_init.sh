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

    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message${NC}"
}

# Function to retry a command with exponential backoff
retry_command() {
    local cmd=$1
    local description=$2
    local max_attempts="${3:-3}"
    local timeout="${4:-5}"
    local attempt=1
    local exit_code=0

    while [[ $attempt -le $max_attempts ]]; do
        log_message "INFO" "Attempt $attempt/$max_attempts: $description"

        eval $cmd
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            log_message "INFO" "$description successful"
            return 0
        fi

        log_message "WARN" "$description failed. Retrying in $timeout seconds..."
        sleep $timeout

        attempt=$((attempt + 1))
        timeout=$((timeout * 2))
    done

    log_message "ERROR" "$description - All attempts failed"
    return $exit_code
}

# Function to check if Docker is installed and running
check_docker() {
    log_message "INFO" "Checking Docker installation..."

    if ! command -v docker &> /dev/null; then
        log_message "ERROR" "Docker is not installed"
        return 1
    fi

    log_message "INFO" "Docker is installed"

    log_message "INFO" "Checking Docker service status..."
    if ! systemctl is-active --quiet docker; then
        log_message "ERROR" "Docker service is not running"
        return 1
    fi

    log_message "INFO" "Docker is running"
    return 0
}

# Function to get IP addresses
get_ips() {
    local interface_type=$1
    local ip_type=$2

    log_message "INFO" "Getting IP addresses (interface_type: $interface_type, ip_type: $ip_type)"

    # Try to get IP from metadata service first
    if [ "$ip_type" == "public" ]; then
        local metadata_ip
        metadata_ip=$(curl -s -m 5 http://169.254.169.254/opc/v1/instance/publicIp 2>/dev/null)
        if [ -n "$metadata_ip" ] && [ "$metadata_ip" != "Not Found" ]; then
            log_message "INFO" "Got public IP from metadata service: $metadata_ip"
            echo "$metadata_ip"
            return 0
        fi
    elif [ "$ip_type" == "private" ]; then
        local metadata_ip
        metadata_ip=$(curl -s -m 5 http://169.254.169.254/opc/v1/instance/privateIp 2>/dev/null)
        if [ -n "$metadata_ip" ] && [ "$metadata_ip" != "Not Found" ]; then
            log_message "INFO" "Got private IP from metadata service: $metadata_ip"
            echo "$metadata_ip"
            return 0
        fi
    fi

    log_message "INFO" "Metadata service failed, falling back to network interface detection"

    # Fall back to network interface detection
    local ip
    if [ "$interface_type" == "primary" ]; then
        if [ "$ip_type" == "public" ]; then
            # Try to get public IP from external service
            ip=$(curl -s -m 5 https://ifconfig.me 2>/dev/null)
            if [ -n "$ip" ]; then
                log_message "INFO" "Got public IP from external service: $ip"
                echo "$ip"
                return 0
            fi
        elif [ "$ip_type" == "private" ]; then
            # Get private IP from network interface
            ip=$(ip addr show | grep -E "inet 10\.|inet 172\.|inet 192\." | grep -v "host lo" | head -1 | awk '{print $2}' | cut -d/ -f1)
            if [ -n "$ip" ]; then
                log_message "INFO" "Got private IP from network interface: $ip"
                echo "$ip"
                return 0
            fi
        fi
    fi

    log_message "ERROR" "Failed to get IP address"
    return 1
}

# Function to initialize Docker Swarm on manager node
init_swarm_manager() {
    local ip=$1

    # Check if already part of a swarm
    if docker info | grep -q "Swarm: active"; then
        log_message "INFO" "This node is already part of an active swarm"
        return 0
    fi

    # Get private IP for swarm communication if not provided
    local private_ip=$ip
    if [ -z "$private_ip" ]; then
        private_ip=$(get_ips "primary" "private")
        if [ -z "$private_ip" ]; then
            log_message "ERROR" "Failed to get private IP for swarm communication"
            return 1
        fi
    fi

    # Open firewall ports for Docker Swarm
    log_message "INFO" "Opening firewall ports for Docker Swarm..."
    firewall-cmd --permanent --add-port=2377/tcp
    firewall-cmd --permanent --add-port=7946/tcp
    firewall-cmd --permanent --add-port=7946/udp
    firewall-cmd --permanent --add-port=4789/udp
    firewall-cmd --reload

    log_message "INFO" "Initializing Docker Swarm on manager node with IP: $private_ip"
    retry_command "docker swarm init --advertise-addr $private_ip" "Swarm initialization" 3 10

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

    # Create required directories for Traefik
    log_message "INFO" "Creating required directories for Traefik..."
    mkdir -p /var/log/traefik
    chmod 755 /var/log/traefik

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

    # Create agent_network if it doesn't exist
    if ! docker network ls | grep -q "agent_network"; then
        log_message "INFO" "Creating agent_network..."
        retry_command "docker network create --driver=overlay --attachable agent_network" "Create agent_network" 3 5
        if [ $? -ne 0 ]; then
            log_message "ERROR" "Failed to create agent_network"
            return 1
        fi
    else
        log_message "INFO" "agent_network already exists"
    fi

    # Create traefik-public network for Pangolin if it doesn't exist
    if ! docker network ls | grep -q "traefik-public"; then
        log_message "INFO" "Creating traefik-public network for Pangolin..."
        retry_command "docker network create --driver=overlay --attachable traefik-public" "Create traefik-public network" 3 5
        if [ $? -ne 0 ]; then
            log_message "WARN" "Failed to create traefik-public network. Trying with a different name..."
            # Try with swarm_ prefix
            retry_command "docker network create --driver=overlay --attachable swarm_traefik-public" "Create swarm_traefik-public network" 3 5
            if [ $? -ne 0 ]; then
                log_message "ERROR" "Failed to create traefik-public network with any name. Pangolin may not work correctly."
                # Don't return error as this is not critical for the main stack
            else
                log_message "INFO" "Created swarm_traefik-public network"
                # Create a symlink for compatibility
                docker network create --driver=overlay --attachable traefik-public || true
            fi
        fi
    else
        log_message "INFO" "traefik-public network already exists"
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

    # Open firewall ports for Docker Swarm
    log_message "INFO" "Opening firewall ports for Docker Swarm..."
    firewall-cmd --permanent --add-port=2377/tcp
    firewall-cmd --permanent --add-port=7946/tcp
    firewall-cmd --permanent --add-port=7946/udp
    firewall-cmd --permanent --add-port=4789/udp
    firewall-cmd --reload

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

    # Open firewall ports for Docker Swarm
    log_message "INFO" "Opening firewall ports for Docker Swarm..."
    firewall-cmd --permanent --add-port=2377/tcp
    firewall-cmd --permanent --add-port=7946/tcp
    firewall-cmd --permanent --add-port=7946/udp
    firewall-cmd --permanent --add-port=4789/udp
    firewall-cmd --reload

    log_message "INFO" "Joining manager node to swarm..."
    retry_command "docker swarm join --token $token $manager_ip:2377" "Join manager to swarm" 3 10

    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to join manager to swarm"
        return 1
    fi

    log_message "INFO" "Manager node successfully joined the swarm"
    return 0
}

# Main function to initialize Docker Swarm
init_docker_swarm() {
    local node_type=$1
    local manager_ip=$2

    log_message "INFO" "Starting Docker Swarm initialization (node_type: $node_type, manager_ip: $manager_ip)"

    # Check Docker installation
    check_docker
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Docker check failed"
        return 1
    fi

    # Get the primary IP address
    local primary_ip
    primary_ip=$(get_ips "primary" "private")
    if [ -z "$primary_ip" ]; then
        log_message "ERROR" "Failed to get primary IP address"
        return 1
    fi

    log_message "INFO" "Primary IP address: $primary_ip"

    # Initialize or join swarm based on node type
    case $node_type in
        "manager")
            if [ -z "$manager_ip" ]; then
                # This is the first manager node
                log_message "INFO" "Initializing first manager node"
                init_swarm_manager "$primary_ip"
                if [ $? -ne 0 ]; then
                    log_message "ERROR" "Failed to initialize first manager node"
                    return 1
                fi

                # Create overlay networks
                create_overlay_networks
                if [ $? -ne 0 ]; then
                    log_message "ERROR" "Failed to create overlay networks"
                    return 1
                fi
            else
                # This is an additional manager node
                log_message "INFO" "Initializing additional manager node"

                # Get join token from manager
                local token=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa opc@$manager_ip "sudo docker swarm join-token manager -q")
                if [ -z "$token" ]; then
                    log_message "ERROR" "Failed to get join token from manager"
                    return 1
                fi

                # Join as manager
                join_manager_node "$manager_ip" "$token"
                if [ $? -ne 0 ]; then
                    log_message "ERROR" "Failed to join as manager"
                    return 1
                fi
            fi
            ;;
        "worker")
            if [ -z "$manager_ip" ]; then
                log_message "ERROR" "Manager IP is required for worker nodes"
                return 1
            fi

            # Get join token from manager
            local token=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa opc@$manager_ip "sudo docker swarm join-token worker -q")
            if [ -z "$token" ]; then
                log_message "ERROR" "Failed to get join token from manager"
                return 1
            fi

            # Join as worker
            join_worker_node "$manager_ip" "$token"
            if [ $? -ne 0 ]; then
                log_message "ERROR" "Failed to join as worker"
                return 1
            fi
            ;;
        *)
            log_message "ERROR" "Invalid node type: $node_type"
            return 1
            ;;
    esac

    log_message "INFO" "Docker Swarm initialization completed successfully"
    return 0
}

# Function to deploy a stack
deploy_stack() {
    local compose_file=$1
    local stack_name=$2

    log_message "INFO" "Deploying stack $stack_name from $compose_file"

    # Check if the compose file exists
    if [ ! -f "$compose_file" ]; then
        log_message "ERROR" "Compose file $compose_file not found"
        return 1
    fi

    # Create Pangolin config file if it doesn't exist
    if [ ! -f "/root/pangolin-config.json" ]; then
        log_message "INFO" "Creating Pangolin config file..."
        cat > /root/pangolin-config.json << EOF
{
  "domain": "admin-pangolin.${domain_name}",
  "adminEmail": "admin@${domain_name}",
  "adminPassword": "${pangolin_admin_password}",
  "jwtSecret": "${pangolin_token}",
  "database": {
    "type": "sqlite",
    "path": "/app/config/pangolin.db"
  },
  "server": {
    "port": 3001,
    "host": "0.0.0.0"
  }
}
EOF
        chmod 644 /root/pangolin-config.json
    fi

    # Verify networks exist
    for network in lb_network traefik-public; do
        if ! docker network ls | grep -q "$network"; then
            log_message "WARN" "Network $network not found. Creating it..."
            docker network create --driver=overlay --attachable $network
            if [ $? -ne 0 ]; then
                log_message "ERROR" "Failed to create network $network"
                # Try with swarm_ prefix
                docker network create --driver=overlay --attachable swarm_$network
            fi
        fi
    done

    # Deploy the stack
    retry_command "docker stack deploy -c $compose_file $stack_name" "Deploy stack $stack_name" 3 10

    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to deploy stack $stack_name"
        return 1
    fi

    log_message "INFO" "Stack $stack_name deployed successfully"
    return 0
}

# Function to check stack status
check_stack_status() {
    local stack_name=$1

    log_message "INFO" "Checking status of stack $stack_name"

    # Check if the stack exists
    if ! docker stack ls | grep -q "$stack_name"; then
        log_message "ERROR" "Stack $stack_name does not exist"
        return 1
    fi

    # Check for services with 0 replicas
    local zero_replicas=$(docker service ls --format "{{.Name}} {{.Replicas}}" | grep "$stack_name" | grep "/0" || true)
    if [ -n "$zero_replicas" ]; then
        log_message "WARN" "Services with 0 replicas running:"
        echo "$zero_replicas"
        return 1
    fi

    log_message "INFO" "Stack $stack_name is running properly"
    return 0
}

# Export functions for use in other scripts
export -f log_message
export -f retry_command
export -f check_docker
export -f get_ips
export -f init_swarm_manager
export -f create_overlay_networks
export -f get_worker_token
export -f get_manager_token
export -f join_worker_node
export -f join_manager_node
export -f init_docker_swarm
export -f deploy_stack
export -f check_stack_status

# If this script is being executed directly, run the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_docker_swarm "$@"
fi
