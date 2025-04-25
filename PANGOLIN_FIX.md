# Pangolin Fix Instructions

This document provides instructions for fixing the Pangolin server 520 error.

## Background

The Pangolin server is experiencing a 520 error when accessed at https://admin-pangolin.throughfire.net. This error occurs because:

1. The Pangolin service is using an incorrect image (nginx:alpine instead of fosrl/pangolin:latest)
2. The service is configured to use port 80 instead of port 3001
3. The service is not properly connected to the traefik-public network
4. The environment variables are not correctly configured

## Fix Instructions

### Method 1: Using the Fix Script

1. Copy the fix_pangolin.sh script to the manager node:
   ```bash
   scp -i ~/.ssh/oci_swarm_key.pem docker_swarm_free/oci-swarm-cluster/fix_pangolin.sh opc@149.130.214.196:/tmp/
   ```

2. SSH into the manager node:
   ```bash
   ssh -i ~/.ssh/oci_swarm_key.pem opc@149.130.214.196
   ```

3. Make the script executable and run it:
   ```bash
   sudo cp /tmp/fix_pangolin.sh /root/
   sudo chmod +x /root/fix_pangolin.sh
   sudo /root/fix_pangolin.sh
   ```

4. Verify that the Pangolin service is running:
   ```bash
   sudo docker service ls | grep pangolin
   ```

### Method 2: Manual Fix

If the fix script doesn't work, you can manually update the Docker Compose file:

1. SSH into the manager node:
   ```bash
   ssh -i ~/.ssh/oci_swarm_key.pem opc@149.130.214.196
   ```

2. Create a backup of the current Docker Compose file:
   ```bash
   sudo cp /root/docker-compose.yml /root/docker-compose.yml.bak
   ```

3. Edit the Docker Compose file:
   ```bash
   sudo vi /root/docker-compose.yml
   ```

4. Add the traefik-public network to the traefik service:
   ```yaml
   networks:
       - lb_network
       - traefik-public
   ```

5. Replace or add the Pangolin service:
   ```yaml
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
   ```

6. Add the pangolin_data volume to the volumes section:
   ```yaml
   volumes:
     registry:
       driver: local
     portainer:
       driver: local
     pangolin_data:
       driver: local
   ```

7. Add the traefik-public network to the networks section:
   ```yaml
   networks:
     lb_network:
       external: true
     agent_network:
       external: true
     traefik-public:
       external: true
   ```

8. Create the traefik-public network if it doesn't exist:
   ```bash
   sudo docker network create --driver=overlay --attachable traefik-public
   ```

9. Deploy the updated stack:
   ```bash
   sudo docker stack deploy -c /root/docker-compose.yml swarm
   ```

## Verification

After applying the fix, you should be able to access the Pangolin admin interface at:
https://admin-pangolin.throughfire.net

Login credentials:
- Email: admin@throughfire.net
- Password: B9D4VcWM62u88Uch7ZoXurupWU560ft7

## Troubleshooting

If you still encounter issues:

1. Check the Pangolin service logs:
   ```bash
   sudo docker service logs swarm_pangolin
   ```

2. Verify that the traefik-public network exists:
   ```bash
   sudo docker network ls | grep traefik-public
   ```

3. Check if the Pangolin service is running:
   ```bash
   sudo docker service ls | grep pangolin
   ```

4. Verify that the Pangolin container is listening on port 3001:
   ```bash
   CONTAINER_ID=$(sudo docker ps | grep pangolin | awk '{print $1}')
   sudo docker exec $CONTAINER_ID netstat -tulpn | grep 3001
   ```
