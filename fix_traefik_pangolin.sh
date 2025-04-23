#!/bin/bash
# Script to fix Traefik and Pangolin setup

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if the private key exists
if [ ! -f ~/.ssh/oci_swarm_key.pem ]; then
    echo -e "${RED}Error: Private key not found!${NC}"
    echo -e "${YELLOW}Please run 'terraform output -raw generated_private_key_pem > ~/.ssh/oci_swarm_key.pem && chmod 600 ~/.ssh/oci_swarm_key.pem'${NC}"
    exit 1
fi

# Get the IP address of the manager instance
MANAGER_IP=$(terraform output -raw app_instance_public_ips | jq -r '.[0]')

if [ -z "$MANAGER_IP" ]; then
    echo -e "${RED}Error: Could not get manager IP address from Terraform output!${NC}"
    exit 1
fi

echo -e "${YELLOW}Manager IP: ${MANAGER_IP}${NC}"

# Check if secrets.tfvars exists
if [ ! -f "secrets.tfvars" ]; then
    echo -e "${RED}Error: secrets.tfvars file not found!${NC}"
    echo -e "${YELLOW}Please create a secrets.tfvars file with your Cloudflare credentials.${NC}"
    exit 1
fi

# Extract Cloudflare credentials from secrets.tfvars
CF_EMAIL=$(grep cloudflare_email secrets.tfvars | cut -d '=' -f2 | tr -d ' "')
CF_API_TOKEN=$(grep cloudflare_api_token secrets.tfvars | cut -d '=' -f2 | tr -d ' "')
DOMAIN_NAME=$(grep domain_name secrets.tfvars | cut -d '=' -f2 | tr -d ' "')

if [ -z "$CF_EMAIL" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}Error: Could not find Cloudflare credentials in secrets.tfvars!${NC}"
    exit 1
fi

# Generate a new Pangolin token if not provided
PANGOLIN_TOKEN=$(grep pangolin_token secrets.tfvars | cut -d '=' -f2 | tr -d ' "')
if [ -z "$PANGOLIN_TOKEN" ]; then
    echo -e "${YELLOW}Generating a new Pangolin token...${NC}"
    PANGOLIN_TOKEN=$(openssl rand -hex 16)
    echo -e "${GREEN}Generated Pangolin token: ${PANGOLIN_TOKEN}${NC}"
    
    # Add the token to secrets.tfvars if not already there
    if ! grep -q "pangolin_token" secrets.tfvars; then
        echo "pangolin_token = \"${PANGOLIN_TOKEN}\"" >> secrets.tfvars
        echo -e "${GREEN}Added Pangolin token to secrets.tfvars${NC}"
    else
        # Update the existing token
        sed -i "s/pangolin_token = \".*\"/pangolin_token = \"${PANGOLIN_TOKEN}\"/" secrets.tfvars
        echo -e "${GREEN}Updated Pangolin token in secrets.tfvars${NC}"
    fi
fi

# Create an updated docker-compose.yml file with the correct Pangolin token
echo -e "${YELLOW}Creating updated docker-compose.yml file...${NC}"
cat > docker-compose.updated.yml << EOF
version: "3.6"

services:
    whoami:
        image: traefik/whoami:v1.6.1
        deploy:
            mode: replicated
            replicas: 1
            labels:
                - traefik.enable=true
                - traefik.docker.network=lb_network
                - traefik.constraint-label=traefik-public
                - traefik.http.routers.whoami.rule=Path(\`/whoami\`)
                - traefik.http.routers.whoami.entrypoints=https,http
                - traefik.http.routers.whoami.tls=true
                - traefik.http.routers.whoami.tls.certresolver=cloudflare
                - traefik.http.services.whoami.loadbalancer.server.port=80
        networks:
            - lb_network

    registry:
        image: registry:2
        ports:
            - 5000:5000
        networks:
            - lb_network
        volumes:
            - registry:/var/lib/registry
        deploy:
            mode: replicated
            replicas: 1
            labels:
                - traefik.enable=true
                - traefik.docker.network=lb_network
                - traefik.constraint-label=traefik-public
                - traefik.http.routers.registry.rule=(Host(\`registry.${DOMAIN_NAME}\`) && PathPrefix(\`/v2/\`))
                - traefik.http.routers.registry-v2.rule=(Host(\`v2.registry.${DOMAIN_NAME}\`) && PathPrefix(\`/v2/\`))
                - traefik.http.routers.registry.entrypoints=https
                - traefik.http.routers.registry.tls=true
                - traefik.http.routers.registry.tls.certresolver=cloudflare
                - traefik.http.routers.registry-v2.entrypoints=https
                - traefik.http.routers.registry-v2.tls=true
                - traefik.http.routers.registry-v2.tls.certresolver=cloudflare
                - traefik.http.services.registry.loadbalancer.server.port=5000
                - traefik.http.services.registry-v2.loadbalancer.server.port=5000
                # Add HTTP router for registry to handle redirects
                - traefik.http.routers.registry-http.rule=(Host(\`registry.${DOMAIN_NAME}\`) && PathPrefix(\`/v2/\`))
                - traefik.http.routers.registry-http.entrypoints=http
                - traefik.http.middlewares.registry-https-redirect.redirectscheme.scheme=https
                - traefik.http.routers.registry-http.middlewares=registry-https-redirect

    agent:
        image: portainer/agent
        environment:
            # REQUIRED: Should be equal to the service name prefixed by "tasks." when
            # deployed inside an overlay network
            AGENT_CLUSTER_ADDR: tasks.swarm_agent
            # AGENT_PORT: 9001
            # LOG_LEVEL: debug
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock
            - /var/lib/docker/volumes:/var/lib/docker/volumes
        networks:
            - agent_network
        deploy:
            mode: global
            placement:
                constraints: [node.platform.os == linux]

    portainer:
        image: portainer/portainer-ce:2.11.1
        command: -H tcp://tasks.swarm_agent:9001 --tlsskipverify
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock
            - portainer:/data
        networks:
            - agent_network
            - lb_network
        deploy:
            mode: replicated
            replicas: 1
            labels:
                - traefik.enable=true
                - traefik.docker.network=lb_network
                - traefik.constraint-label=traefik-public
                - traefik.http.routers.portainer.rule=(Host(\`dev-oci.${DOMAIN_NAME}\`) && PathPrefix(\`/\`))
                - traefik.http.routers.portainer-v2-11-1.rule=(Host(\`v2-11-1.dev-oci.${DOMAIN_NAME}\`) && PathPrefix(\`/\`))
                - traefik.http.routers.portainer.entrypoints=https
                - traefik.http.routers.portainer.tls=true
                - traefik.http.routers.portainer.tls.certresolver=cloudflare
                - traefik.http.routers.portainer-v2-11-1.entrypoints=https
                - traefik.http.routers.portainer-v2-11-1.tls=true
                - traefik.http.routers.portainer-v2-11-1.tls.certresolver=cloudflare
                - traefik.http.services.portainer.loadbalancer.server.port=9000
                - traefik.http.services.portainer-v2-11-1.loadbalancer.server.port=9000
                # Add HTTP router for portainer to handle redirects
                - traefik.http.routers.portainer-http.rule=(Host(\`dev-oci.${DOMAIN_NAME}\`) && PathPrefix(\`/\`))
                - traefik.http.routers.portainer-http.entrypoints=http
                - traefik.http.middlewares.portainer-https-redirect.redirectscheme.scheme=https
                - traefik.http.routers.portainer-http.middlewares=portainer-https-redirect

    traefik:
        image: traefik:v2.6.1
        ports:
            - target: 80
              published: 80
              protocol: tcp
              mode: host
            - target: 443
              published: 443
              protocol: tcp
              mode: host
        deploy:
            mode: global
            placement:
                constraints:
                    - node.role == manager
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - /var/log/traefik:/var/log/traefik:rw
            - registry:/data
            - ./traefik_dynamic_conf.toml:/etc/traefik/dynamic_conf.toml:ro
        command:
            - --providers.docker
            - --providers.docker.constraints=Label(\`traefik.constraint-label\`, \`traefik-public\`)
            - --providers.docker.exposedbydefault=false
            - --providers.docker.swarmmode
            - --providers.file.directory=/etc/traefik
            - --providers.file.watch=true
            - --entrypoints.http.address=:80
            - --entrypoints.https.address=:443
            - --serversTransport.insecureSkipVerify=true
            - --certificatesresolvers.cloudflare.acme.email=${CF_EMAIL}
            - --certificatesresolvers.cloudflare.acme.storage=/data/acme.json
            - --certificatesresolvers.cloudflare.acme.dnschallenge=true
            - --certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare
            - --entryPoints.http.forwardedHeaders.trustedIPs=127.0.0.1/32,10.0.0.0/8
            # Add global HTTP to HTTPS redirect
            - --entrypoints.http.http.redirections.entryPoint.to=https
            - --entrypoints.http.http.redirections.entryPoint.scheme=https
            - --entrypoints.http.http.redirections.entrypoint.permanent=true
            # Add access logs
            - --accesslog=true
            - --accesslog.filepath=/var/log/traefik/access.log
            - --log=true
            - --log.filepath=/var/log/traefik/traefik.log
            - --log.level=DEBUG
            # Security headers
            - --entrypoints.https.http.tls=true
            - --entrypoints.https.http.middlewares=secure-headers@file
            # API and dashboard configuration
            - --api.dashboard=true
            - --api.insecure=false
            - --ping=true
        environment:
            - CLOUDFLARE_EMAIL=${CF_EMAIL}
            - CLOUDFLARE_DNS_API_TOKEN=${CF_API_TOKEN}
        networks:
            - lb_network

    # Add Pangolin (or alternative like Cloudflare Tunnel)
    pangolin:
        image: ghcr.io/dperson/pangolin:latest
        restart: unless-stopped
        environment:
            - TOKEN=${PANGOLIN_TOKEN}
            - DOMAIN=${DOMAIN_NAME}
        networks:
            - lb_network
        deploy:
            mode: replicated
            replicas: 1
            placement:
                constraints:
                    - node.role == manager

    # Example local service proxy
    localproxy:
        image: nginx:alpine
        networks:
            - lb_network
        deploy:
            labels:
                - traefik.enable=true
                - traefik.docker.network=lb_network
                - traefik.http.routers.localproxy.rule=Host(\`local.${DOMAIN_NAME}\`)
                - traefik.http.routers.localproxy-alpine.rule=Host(\`alpine.local.${DOMAIN_NAME}\`)
                - traefik.http.routers.localproxy.entrypoints=https
                - traefik.http.routers.localproxy.tls=true
                - traefik.http.routers.localproxy.tls.certresolver=cloudflare
                - traefik.http.routers.localproxy-alpine.entrypoints=https
                - traefik.http.routers.localproxy-alpine.tls=true
                - traefik.http.routers.localproxy-alpine.tls.certresolver=cloudflare
                - traefik.http.services.localproxy.loadbalancer.server.port=80
                - traefik.http.services.localproxy-alpine.loadbalancer.server.port=80
                # Add HTTP router for localproxy to handle redirects
                - traefik.http.routers.localproxy-http.rule=Host(\`local.${DOMAIN_NAME}\`)
                - traefik.http.routers.localproxy-http.entrypoints=http
                - traefik.http.middlewares.localproxy-https-redirect.redirectscheme.scheme=https
                - traefik.http.routers.localproxy-http.middlewares=localproxy-https-redirect
        volumes:
            - ./nginx.conf:/etc/nginx/nginx.conf:ro

volumes:
  registry:
    driver: s3fs
    name: "oci-registry-ppQ6"
  portainer:
    driver: s3fs
    name: "oci-portainer-ppQ6"

networks:
  # Use the previously created public network "traefik-public", shared with other
  # services that need to be publicly available via this Traefik
  lb_network:
    external: true
  agent_network:
    external: true
EOF

# Copy the updated docker-compose.yml file to the manager
echo -e "${YELLOW}Copying the updated docker-compose.yml file to the manager...${NC}"
scp -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem docker-compose.updated.yml opc@${MANAGER_IP}:/tmp/docker-compose.yml

# Copy the nginx.conf file to the manager
echo -e "${YELLOW}Copying the nginx.conf file to the manager...${NC}"
scp -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem nginx.conf opc@${MANAGER_IP}:/tmp/nginx.conf

# Update the files on the manager and restart the stack
echo -e "${YELLOW}Updating files on the manager and restarting the stack...${NC}"
ssh -o StrictHostKeyChecking=no -i ~/.ssh/oci_swarm_key.pem opc@${MANAGER_IP} "
    sudo mv /tmp/docker-compose.yml /root/docker-compose.yml
    sudo mv /tmp/nginx.conf /root/nginx.conf
    sudo chmod 644 /root/docker-compose.yml /root/nginx.conf
    
    # Create the log directory if it doesn't exist
    sudo mkdir -p /var/log/traefik
    
    # Remove the old stack and deploy the new one
    sudo docker stack rm swarm
    sleep 10
    sudo docker stack deploy -c /root/docker-compose.yml swarm
"

echo -e "${GREEN}Traefik and Pangolin setup fixed!${NC}"
echo -e "${YELLOW}Now run 'terraform apply -var-file=secrets.tfvars' to ensure Terraform state is in sync.${NC}"
