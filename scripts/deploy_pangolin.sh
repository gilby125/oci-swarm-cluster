#!/bin/bash

# Deploy Pangolin stack to Docker Swarm
# This script deploys the Pangolin stack using the pangolin-compose.yml file

set -e

# Log function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check if running on manager node
if ! docker node ls &>/dev/null; then
  log "ERROR: This script must be run on a Docker Swarm manager node"
  exit 1
fi

# Deploy Pangolin stack
log "Deploying Pangolin stack..."
docker stack deploy -c /root/pangolin-compose.yml pangolin

# Check if deployment was successful
if [ $? -eq 0 ]; then
  log "Pangolin stack deployed successfully"
else
  log "ERROR: Failed to deploy Pangolin stack"
  exit 1
fi

# Wait for services to start
log "Waiting for Pangolin services to start..."
sleep 10

# Check service status
log "Checking Pangolin service status..."
docker service ls | grep pangolin

log "Pangolin deployment completed"
log "You can access the Pangolin admin interface at: https://admin-pangolin.throughfire.net"
log "Admin email: admin@throughfire.net"
log "Admin password: B9D4VcWM62u88Uch7ZoXurupWU560ft7"

exit 0
