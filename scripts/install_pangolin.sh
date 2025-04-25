#!/bin/bash

# Install Pangolin on Docker Swarm
# This script installs the full Pangolin application to replace the compatibility mode version

set -e

# Generate secure passwords
ADMIN_PASSWORD=$(openssl rand -base64 16)
JWT_SECRET=$(openssl rand -base64 32)

# Create environment file
cat > pangolin.env << EOF
PANGOLIN_ADMIN_PASSWORD=$ADMIN_PASSWORD
PANGOLIN_JWT_SECRET=$JWT_SECRET
EOF

# Deploy Pangolin to Docker Swarm
docker stack deploy -c pangolin-compose.yml pangolin

# Output credentials
echo "Pangolin has been installed!"
echo "========================================"
echo "URL: https://admin-pangolin.throughfire.net"
echo "Admin Email: admin@throughfire.net"
echo "Admin Password: $ADMIN_PASSWORD"
echo "========================================"
echo "Please save these credentials securely."
echo "You can change the password after logging in."
