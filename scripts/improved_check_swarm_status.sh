#!/bin/bash
# Improved script to check the status of Docker Swarm services with better error handling and recovery

# Function to log messages with timestamp
log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${level}: ${message}"
}

# Function to restart a service
restart_service() {
    local service_name=$1
    log_message "INFO" "Attempting to restart service: $service_name"
    
    # Force update the service to restart it
    docker service update --force swarm_$service_name
    
    # Check if the service was restarted successfully
    if [ $? -eq 0 ]; then
        log_message "INFO" "Service $service_name restarted successfully"
        return 0
    else
        log_message "ERROR" "Failed to restart service $service_name"
        return 1
    fi
}

# Function to recreate a network
recreate_network() {
    local network_name=$1
    log_message "INFO" "Attempting to recreate network: $network_name"
    
    # Remove the network if it exists
    if docker network ls | grep -q "$network_name"; then
        log_message "INFO" "Removing existing network: $network_name"
        docker network rm "$network_name"
        sleep 5
    fi
    
    # Create the network
    log_message "INFO" "Creating network: $network_name"
    docker network create --driver=overlay --attachable "$network_name"
    
    # Check if the network was created successfully
    if [ $? -eq 0 ]; then
        log_message "INFO" "Network $network_name created successfully"
        return 0
    else
        log_message "ERROR" "Failed to create network $network_name"
        return 1
    fi
}

log_message "INFO" "Starting Docker Swarm status check..."

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
    log_message "ERROR" "Docker is not running!"
    log_message "INFO" "Attempting to start Docker..."
    systemctl start docker
    sleep 5
    if ! systemctl is-active --quiet docker; then
        log_message "ERROR" "Failed to start Docker. Please check the Docker service."
        exit 1
    fi
    log_message "INFO" "Docker started successfully"
fi

# Check if node is part of a swarm
if ! docker info | grep -q "Swarm: active"; then
    log_message "ERROR" "This node is not part of an active swarm!"
    
    # Check if this is supposed to be a manager node
    if [[ $(hostname) =~ -0$ ]]; then
        log_message "INFO" "This appears to be a manager node, attempting to initialize swarm..."
        docker swarm init --advertise-addr enp0s3
        if [ $? -eq 0 ]; then
            log_message "INFO" "Swarm initialized successfully"
        else
            log_message "ERROR" "Failed to initialize swarm"
            exit 1
        fi
    else
        log_message "ERROR" "This is not a manager node, cannot initialize swarm"
        exit 1
    fi
fi

# Check swarm node status
log_message "INFO" "Swarm Nodes:"
docker node ls

# Check for nodes in Down state
down_nodes=$(docker node ls | grep "Down" || true)
if [ -n "$down_nodes" ]; then
    log_message "WARN" "Some nodes are in Down state:"
    echo "$down_nodes"
fi

# Check swarm services
log_message "INFO" "Swarm Services:"
docker service ls

# Check for services with 0 replicas running
zero_replicas=$(docker service ls --format "{{.Name}} {{.Replicas}}" | grep "/0" || true)
if [ -n "$zero_replicas" ]; then
    log_message "WARN" "Services with 0 replicas running:"
    echo "$zero_replicas"
    
    # Attempt to restart services with 0 replicas
    for service in $(echo "$zero_replicas" | awk '{print $1}'); do
        log_message "INFO" "Attempting to restart service: $service"
        docker service update --force "$service"
    done
fi

# Check network status
log_message "INFO" "Network Status:"
docker network ls | grep -E 'lb_network|agent_network'

# Check if required networks exist
if ! docker network ls | grep -q "lb_network"; then
    log_message "WARN" "lb_network is missing!"
    recreate_network "lb_network"
fi

if ! docker network ls | grep -q "agent_network"; then
    log_message "WARN" "agent_network is missing!"
    recreate_network "agent_network"
fi

# Check for any service logs with errors
log_message "INFO" "Checking for service errors..."
for service in $(docker service ls --format "{{.Name}}"); do
    # Get the container IDs for this service
    containers=$(docker ps -q --filter "name=$service")
    if [ -n "$containers" ]; then
        for container in $containers; do
            # Check for errors in the logs (last 50 lines)
            errors=$(docker logs --tail 50 $container 2>&1 | grep -i "error\|exception\|fatal" || true)
            if [ -n "$errors" ]; then
                log_message "WARN" "Errors found in $service:"
                echo "$errors" | head -5
                log_message "INFO" "Use 'docker logs $container' for full logs"
                
                # Check if service needs to be restarted based on error patterns
                if echo "$errors" | grep -qi "connection refused\|timeout\|unreachable\|no such network"; then
                    log_message "INFO" "Error suggests connectivity issue, attempting to restart service"
                    restart_service $(echo "$service" | sed 's/swarm_//')
                fi
            fi
        done
    fi
done

# Check Registry status
log_message "INFO" "Checking Registry status..."
registry_container=$(docker ps -q --filter "name=swarm_registry" || true)
if [ -n "$registry_container" ]; then
    log_message "INFO" "Registry is running (Container ID: $registry_container)"
    
    # Check if Registry API is responding
    if docker exec $registry_container wget -q -O- http://localhost:5000/v2/ 2>/dev/null | grep -q "{}"; then
        log_message "INFO" "Registry API is responding correctly"
    else
        log_message "WARN" "Registry API is not responding correctly"
        restart_service "registry"
    fi
else
    log_message "WARN" "Registry is not running!"
    restart_service "registry"
fi

# Check Portainer status
log_message "INFO" "Checking Portainer status..."
portainer_container=$(docker ps -q --filter "name=swarm_portainer" || true)
if [ -n "$portainer_container" ]; then
    log_message "INFO" "Portainer is running (Container ID: $portainer_container)"
    
    # Check if Portainer API is responding
    if docker exec $portainer_container wget -q -O- http://localhost:9000/api/status 2>/dev/null | grep -q "Version"; then
        log_message "INFO" "Portainer API is responding correctly"
    else
        log_message "WARN" "Portainer API is not responding correctly"
        restart_service "portainer"
    fi
else
    log_message "WARN" "Portainer is not running!"
    restart_service "portainer"
fi

# Check Traefik status
log_message "INFO" "Checking Traefik status..."
traefik_container=$(docker ps -q --filter "name=swarm_traefik" || true)
if [ -n "$traefik_container" ]; then
    log_message "INFO" "Traefik is running (Container ID: $traefik_container)"
    
    # Check if Traefik API is responding
    if docker exec $traefik_container wget -q -O- http://localhost:8080/api/version 2>/dev/null | grep -q "Version"; then
        log_message "INFO" "Traefik API is responding correctly"
    else
        log_message "WARN" "Traefik API is not responding correctly"
        restart_service "traefik"
    fi
    
    # Check for certificate issues
    cert_issues=$(docker logs $traefik_container 2>&1 | grep -i "certificate\|tls\|acme" | grep -i "error\|fail\|invalid" || true)
    if [ -n "$cert_issues" ]; then
        log_message "WARN" "Certificate issues detected:"
        echo "$cert_issues" | head -5
    fi
else
    log_message "WARN" "Traefik is not running!"
    restart_service "traefik"
fi

# Check Pangolin status
log_message "INFO" "Checking Pangolin status..."
pangolin_container=$(docker ps -q --filter "name=swarm_pangolin" || true)
if [ -n "$pangolin_container" ]; then
    log_message "INFO" "Pangolin is running (Container ID: $pangolin_container)"
else
    log_message "WARN" "Pangolin is not running!"
    restart_service "pangolin"
fi

# Final status check
log_message "INFO" "Final service status:"
docker service ls

log_message "INFO" "Status check and recovery complete!"
