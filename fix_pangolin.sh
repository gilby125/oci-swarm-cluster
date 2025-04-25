#!/bin/bash

# Script to fix Pangolin configuration in Docker Compose file
# This script should be run on the Docker Swarm manager node

set -e

echo "Creating backup of current Docker Compose file..."
cp /root/docker-compose.yml /root/docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)

echo "Checking if traefik-public network exists..."
if ! docker network ls | grep -q traefik-public; then
  echo "Creating traefik-public network..."
  docker network create --driver=overlay --attachable traefik-public
fi

echo "Updating Docker Compose file with proper Pangolin configuration..."

# Add traefik-public network to traefik service
sed -i '/networks:/,/lb_network/ s/- lb_network/- lb_network\n            - traefik-public/' /root/docker-compose.yml

# Add Pangolin service
cat << 'EOF' > /tmp/pangolin_service.txt
    # Pangolin - Secure tunneled reverse proxy with identity and access management
    pangolin:
        image: fosrl/pangolin:latest
        ports:
            - "3001:3001"
        environment:
            - PANGOLIN_DOMAIN=admin-pangolin.throughfire.net
            - PANGOLIN_ADMIN_EMAIL=admin@throughfire.net
            - PANGOLIN_ADMIN_PASSWORD=B9D4VcWM62u88Uch7ZoXurupWU560ft7
            - PANGOLIN_JWT_SECRET=B9D4VcWM62u88Uch7ZoXurupWU560ft7
            - PANGOLIN_DB_TYPE=sqlite
            - PANGOLIN_DB_PATH=/data/pangolin.db
        volumes:
            - pangolin_data:/data
        networks:
            - lb_network
            - traefik-public
        deploy:
            mode: replicated
            replicas: 1
            placement:
                constraints:
                    - node.role == manager
            labels:
                - traefik.enable=true
                - traefik.docker.network=lb_network
                - traefik.constraint-label=traefik-public
                - traefik.http.routers.pangolin.rule=Host(`admin-pangolin.throughfire.net`)
                - traefik.http.routers.pangolin.entrypoints=https
                - traefik.http.routers.pangolin.tls=true
                - traefik.http.routers.pangolin.tls.certresolver=cloudflare
                - traefik.http.services.pangolin.loadbalancer.server.port=3001
                # Add HTTP router for pangolin to handle redirects
                - traefik.http.routers.pangolin-http.rule=Host(`admin-pangolin.throughfire.net`)
                - traefik.http.routers.pangolin-http.entrypoints=http
                - traefik.http.middlewares.pangolin-https-redirect.redirectscheme.scheme=https
                - traefik.http.routers.pangolin-http.middlewares=pangolin-https-redirect
EOF

# Replace or add Pangolin service
if grep -q "# Pangolin" /root/docker-compose.yml; then
  # Replace existing Pangolin section
  sed -i '/# Pangolin/,/# Example local service proxy/c\'"$(cat /tmp/pangolin_service.txt)"'\n\n    # Example local service proxy' /root/docker-compose.yml
else
  # Add Pangolin service before the localproxy service
  sed -i '/# Example local service proxy/i\'"$(cat /tmp/pangolin_service.txt)"'\n' /root/docker-compose.yml
fi

# Add pangolin_data volume
if ! grep -q "pangolin_data:" /root/docker-compose.yml; then
  sed -i '/volumes:/a\  pangolin_data:\n    driver: local' /root/docker-compose.yml
fi

# Add traefik-public network if not already present
if ! grep -q "traefik-public:" /root/docker-compose.yml; then
  sed -i '/networks:/a\  traefik-public:\n    external: true' /root/docker-compose.yml
fi

echo "Docker Compose file updated successfully."
echo "Deploying updated stack..."
docker stack deploy -c /root/docker-compose.yml swarm

echo "Waiting for services to start..."
sleep 10

echo "Checking service status..."
docker service ls | grep pangolin

echo "Pangolin fix completed. You should now be able to access the Pangolin admin interface at:"
echo "https://admin-pangolin.throughfire.net"
echo "Admin email: admin@throughfire.net"
echo "Admin password: B9D4VcWM62u88Uch7ZoXurupWU560ft7"
