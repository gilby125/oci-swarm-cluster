#!/bin/bash

# Script to fix the Pangolin service configuration

# Set up error handling
set -e
trap 'echo "Error on line $LINENO. Exiting..."; exit 1' ERR

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Pangolin service fix...${NC}"

# Create Pangolin configuration file
echo -e "${GREEN}Creating Pangolin configuration file...${NC}"
cat > /tmp/pangolin-config.json << 'EOF'
{
  "domain": "admin-pangolin.throughfire.net",
  "adminEmail": "admin@throughfire.net",
  "adminPassword": "tXQ#BaOqZ~{15]2A",
  "jwtSecret": "3yS2WSVUWgVH0xxevZ2o1J53MxfqM404",
  "database": {
    "type": "sqlite",
    "path": "/data/pangolin.db"
  },
  "server": {
    "port": 3001,
    "host": "0.0.0.0"
  }
}
EOF

# Copy the configuration file to the manager node
echo -e "${GREEN}Copying configuration file to manager node...${NC}"
scp -i id_rsa -o StrictHostKeyChecking=no /tmp/pangolin-config.json opc@149.130.209.161:/home/opc/

# SSH to the manager node and perform the necessary operations
echo -e "${GREEN}Connecting to manager node to update Pangolin service...${NC}"
ssh -i id_rsa -o StrictHostKeyChecking=no opc@149.130.209.161 << 'ENDSSH'
# Copy the configuration file to the root directory
sudo cp /home/opc/pangolin-config.json /root/
sudo chmod 644 /root/pangolin-config.json

# Create a new Docker Compose file for Pangolin
sudo bash -c 'cat > /root/pangolin-compose.yml << EOF
version: "3.8"

services:
  pangolin:
    image: fosrl/pangolin:latest
    ports:
      - "3001:3001"
    environment:
      - PANGOLIN_DOMAIN=admin-pangolin.throughfire.net
      - PANGOLIN_ADMIN_EMAIL=admin@throughfire.net
      - PANGOLIN_ADMIN_PASSWORD=tXQ#BaOqZ~{15]2A
      - PANGOLIN_JWT_SECRET=3yS2WSVUWgVH0xxevZ2o1J53MxfqM404
      - PANGOLIN_DB_TYPE=sqlite
      - PANGOLIN_DB_PATH=/data/pangolin.db
      - PANGOLIN_CONFIG_PATH=/config/pangolin-config.json
    volumes:
      - pangolin_data:/data
      - /root/pangolin-config.json:/config/pangolin-config.json:ro
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
        - "traefik.enable=true"
        - "traefik.docker.network=traefik-public"
        - "traefik.constraint-label=traefik-public"
        - "traefik.http.routers.pangolin.rule=Host(\`admin-pangolin.throughfire.net\`)"
        - "traefik.http.routers.pangolin.entrypoints=https"
        - "traefik.http.routers.pangolin.tls=true"
        - "traefik.http.routers.pangolin.tls.certresolver=cloudflare"
        - "traefik.http.services.pangolin.loadbalancer.server.port=3001"
        - "traefik.http.routers.pangolin-http.rule=Host(\`admin-pangolin.throughfire.net\`)"
        - "traefik.http.routers.pangolin-http.entrypoints=http"
        - "traefik.http.middlewares.pangolin-https-redirect.redirectscheme.scheme=https"
        - "traefik.http.routers.pangolin-http.middlewares=pangolin-https-redirect"

networks:
  lb_network:
    external: true
  traefik-public:
    external:
      name: swarm_traefik-public

volumes:
  pangolin_data:
    driver: local
EOF'

# Remove the existing Pangolin service
echo "Removing existing Pangolin service..."
sudo docker service rm swarm_pangolin || true

# Deploy the new Pangolin service
echo "Deploying new Pangolin service..."
sudo docker stack deploy -c /root/pangolin-compose.yml pangolin

# Check the status of the Pangolin service
echo "Checking Pangolin service status..."
sleep 5
sudo docker service ls | grep pangolin
ENDSSH

echo -e "${GREEN}Pangolin service fix completed.${NC}"
echo -e "${YELLOW}You should now be able to access the Pangolin admin interface at:${NC}"
echo -e "${GREEN}https://admin-pangolin.throughfire.net${NC}"
echo -e "${YELLOW}Login with:${NC}"
echo -e "${GREEN}Email: admin@throughfire.net${NC}"
echo -e "${GREEN}Password: tXQ#BaOqZ~{15]2A${NC}"
