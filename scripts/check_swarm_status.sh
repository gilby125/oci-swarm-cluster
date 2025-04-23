#!/bin/bash
# Script to check the status of Docker Swarm services

# No colors in output for cloud-init compatibility

echo "Checking Docker Swarm status..."

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

# Check swarm node status
echo "\nSwarm Nodes:"
docker node ls

# Check swarm services
echo "\nSwarm Services:"
docker service ls

# Check for services with 0 replicas running
zero_replicas=$(docker service ls --format "{{.Name}} {{.Replicas}}" | grep "/0" || true)
if [ -n "$zero_replicas" ]; then
    echo "\nServices with 0 replicas running:"
    echo "$zero_replicas"
fi

# Check network status
echo "\nNetwork Status:"
docker network ls | grep -E 'lb_network|agent_network'

# Check for any service logs with errors
echo "\nChecking for service errors..."
for service in $(docker service ls --format "{{.Name}}"); do
    # Get the container IDs for this service
    containers=$(docker ps -q --filter "name=$service")
    if [ -n "$containers" ]; then
        for container in $containers; do
            # Check for errors in the logs (last 50 lines)
            errors=$(docker logs --tail 50 $container 2>&1 | grep -i "error\|exception\|fatal" || true)
            if [ -n "$errors" ]; then
                echo "Errors found in $service:"
                echo "$errors" | head -5
                echo "Use 'docker logs $container' for full logs"
            fi
        done
    fi
done

# Check Traefik status specifically
echo "\nChecking Traefik status..."
traefik_container=$(docker ps -q --filter "name=swarm_traefik")
if [ -n "$traefik_container" ]; then
    echo "Traefik is running (Container ID: $traefik_container)"

    # Check if Traefik is serving the dashboard
    if docker exec $traefik_container wget -q -O- http://localhost:8080/api/rawdata 2>/dev/null | grep -q "routers"; then
        echo "Traefik API is responding correctly"
    else
        echo "Traefik API is not responding correctly"
    fi

    # Check for certificate issues
    cert_issues=$(docker logs $traefik_container 2>&1 | grep -i "certificate\|tls\|acme" | grep -i "error\|fail\|invalid" || true)
    if [ -n "$cert_issues" ]; then
        echo "Certificate issues detected:"
        echo "$cert_issues" | head -5
    fi
else
    echo "Traefik is not running!"
fi

# Check Registry status
echo "\nChecking Registry status..."
registry_container=$(docker ps -q --filter "name=swarm_registry")
if [ -n "$registry_container" ]; then
    echo "Registry is running (Container ID: $registry_container)"

    # Check if Registry API is responding
    if docker exec $registry_container wget -q -O- http://localhost:5000/v2/ 2>/dev/null | grep -q "{}"; then
        echo "Registry API is responding correctly"
    else
        echo "Registry API is not responding correctly"
    fi
else
    echo "Registry is not running!"
fi

# Check Portainer status
echo "\nChecking Portainer status..."
portainer_container=$(docker ps -q --filter "name=swarm_portainer")
if [ -n "$portainer_container" ]; then
    echo "Portainer is running (Container ID: $portainer_container)"

    # Check if Portainer API is responding
    if docker exec $portainer_container wget -q -O- http://localhost:9000/api/status 2>/dev/null | grep -q "Version"; then
        echo "Portainer API is responding correctly"
    else
        echo "Portainer API is not responding correctly"
    fi
else
    echo "Portainer is not running!"
fi

echo "\nStatus check complete!"
