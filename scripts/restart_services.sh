#!/bin/bash
# Script to restart Docker Swarm services if they're not running properly

# No colors in output for cloud-init compatibility

echo "Checking and restarting services if needed..."

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
    echo "Docker is not running!"
    echo "Attempting to start Docker..."
    sudo systemctl start docker
    sleep 5
    if ! systemctl is-active --quiet docker; then
        echo "Failed to start Docker. Please check the Docker service."
        exit 1
    fi
fi

# Check if node is part of a swarm
if ! docker info | grep -q "Swarm: active"; then
    echo "This node is not part of an active swarm!"
    exit 1
fi

# Function to restart a service
restart_service() {
    local service=$1
    echo "Restarting $service..."
    docker service update --force $service
    echo "$service restart initiated."
}

# Check for services with 0 replicas running
zero_replicas=$(docker service ls --format "{{.Name}} {{.Replicas}}" | grep "/0" || true)
if [ -n "$zero_replicas" ]; then
    echo "\nServices with 0 replicas running:"
    echo "$zero_replicas"

    # Extract service names and restart them
    for service in $(echo "$zero_replicas" | awk '{print $1}'); do
        restart_service $service
    done
fi

# Check Traefik status
traefik_container=$(docker ps -q --filter "name=swarm_traefik")
if [ -z "$traefik_container" ]; then
    echo "Traefik is not running!"
    restart_service swarm_traefik
else
    # Check if Traefik is serving the dashboard
    if ! docker exec $traefik_container wget -q -O- http://localhost:8080/api/rawdata 2>/dev/null | grep -q "routers"; then
        echo "Traefik API is not responding correctly"
        restart_service swarm_traefik
    fi
fi

# Check Registry status
registry_container=$(docker ps -q --filter "name=swarm_registry")
if [ -z "$registry_container" ]; then
    echo "Registry is not running!"
    restart_service swarm_registry
else
    # Check if Registry API is responding
    if ! docker exec $registry_container wget -q -O- http://localhost:5000/v2/ 2>/dev/null | grep -q "{}"; then
        echo "Registry API is not responding correctly"
        restart_service swarm_registry
    fi
fi

# Check Portainer status
portainer_container=$(docker ps -q --filter "name=swarm_portainer")
if [ -z "$portainer_container" ]; then
    echo "Portainer is not running!"
    restart_service swarm_portainer
else
    # Check if Portainer API is responding
    if ! docker exec $portainer_container wget -q -O- http://localhost:9000/api/status 2>/dev/null | grep -q "Version"; then
        echo "Portainer API is not responding correctly"
        restart_service swarm_portainer
    fi
fi

# Check network status
if ! docker network ls | grep -q "lb_network"; then
    echo "lb_network is missing!"
    echo "Creating lb_network overlay network..."
    docker network create -d overlay lb_network
fi

if ! docker network ls | grep -q "agent_network"; then
    echo "agent_network is missing!"
    echo "Creating agent_network overlay network..."
    docker network create -d overlay agent_network
fi

echo "\nService check and restart complete!"
echo "Current service status:"
docker service ls
