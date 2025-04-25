#!/bin/bash -x
# Copyright (c) 2019, 2020 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Improved setup script for Docker Swarm with better error handling and retry logic

# Function to log messages with timestamp
log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${level}: ${message}"
}

# Function to retry a command
retry_command() {
    local cmd=$1
    local description=$2
    local max_attempts=${3:-5}
    local delay=${4:-5}
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_message "INFO" "Attempt $attempt/$max_attempts: $description"
        eval $cmd
        if [ $? -eq 0 ]; then
            log_message "INFO" "$description - Successful"
            return 0
        else
            log_message "WARN" "$description - Failed (Attempt $attempt/$max_attempts)"
            if [ $attempt -lt $max_attempts ]; then
                log_message "INFO" "Retrying in $delay seconds..."
                sleep $delay
            fi
            attempt=$((attempt+1))
        fi
    done
    
    log_message "ERROR" "$description - All attempts failed"
    return 1
}

# Setup GlusterFS and Docker
log_message "INFO" "Setting up GlusterFS and Docker..."
retry_command "dnf -y install oracle-gluster-release-el8" "Install Oracle Gluster release" 3 5
retry_command "dnf config-manager --enable ol8_gluster_appstream ol8_baseos_latest ol8_appstream" "Enable repositories" 3 5

log_message "INFO" "Creating filesystem image for GlusterFS..."
dd if=/dev/zero of=/home/fs.img count=0 bs=1 seek=20G
mkfs.xfs -f -i size=512 -L glusterfs /home/fs.img
mkdir -p /data/glusterfs/myvolume/mybrick
echo '/home/fs.img /data/glusterfs/myvolume/mybrick xfs defaults  0 0' >> /etc/fstab
mount -a && df

log_message "INFO" "Setting up Docker repositories..."
retry_command "dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo" "Add Docker repository" 3 5
sed -i "s/\$releasever/8/g" /etc/yum.repos.d/docker-ce.repo

log_message "INFO" "Installing GlusterFS and Docker..."
retry_command "dnf -y install glusterfs-server docker-ce docker-ce-cli containerd.io" "Install GlusterFS and Docker" 3 10

log_message "INFO" "Enabling and starting GlusterFS and Docker services..."
systemctl enable --now glusterd
systemctl enable --now docker

# Verify Docker is running
if ! systemctl is-active --quiet docker; then
    log_message "ERROR" "Docker service failed to start"
    systemctl status docker
    exit 1
fi

log_message "INFO" "Loading environment variables..."
source /root/swarm.env
export $(cut -d= -f1 /root/swarm.env)

# Install Docker plugins with retry logic
log_message "INFO" "Installing Docker plugins..."
retry_command "docker plugin install --alias glusterfs mochoa/glusterfs-volume-plugin-aarch64 --grant-all-permissions --disable" "Install GlusterFS plugin" 3 10
retry_command "docker plugin install --alias s3fs mochoa/s3fs-volume-plugin-aarch64 --grant-all-permissions --disable" "Install S3FS plugin" 3 10

# Get hostname and extract node number
my_hostname=$(hostname)
my_base_hostname=$(echo $my_hostname | sed 's/-[0-9]*$//')
node_number=$(echo $my_hostname | grep -o '[0-9]*$')

# Functions for GlusterFS setup
create_gluster_vol() {
    log_message "INFO" "Creating GlusterFS volume..."
    
    # Wait for peer to be ready
    peer_host="$my_base_hostname-1"
    log_message "INFO" "Waiting for peer $peer_host to be ready..."
    
    # Retry peer probe with timeout
    local max_attempts=30
    local attempt=1
    local delay=10
    
    while [ $attempt -le $max_attempts ]; do
        log_message "INFO" "Attempt $attempt/$max_attempts: Probing peer $peer_host"
        gluster peer probe $peer_host
        if [ $? -eq 0 ]; then
            log_message "INFO" "Peer probe successful"
            break
        else
            log_message "WARN" "Peer probe failed (Attempt $attempt/$max_attempts)"
            if [ $attempt -lt $max_attempts ]; then
                log_message "INFO" "Retrying in $delay seconds..."
                sleep $delay
            fi
            attempt=$((attempt+1))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_message "WARN" "Could not probe peer after $max_attempts attempts, continuing anyway..."
    fi
    
    # Create the volume
    log_message "INFO" "Creating GlusterFS volume..."
    gluster volume create myvolume replica 2 $my_hostname:/data/glusterfs/myvolume/mybrick $peer_host:/data/glusterfs/myvolume/mybrick force
    
    # Start the volume
    log_message "INFO" "Starting GlusterFS volume..."
    gluster volume start myvolume
    
    # Enable Docker plugins
    log_message "INFO" "Enabling Docker plugins..."
    docker plugin enable glusterfs
    docker plugin enable s3fs
}

peer_ready() {
    gluster peer probe $1 > /dev/null 2>&1
}

volume_ready() {
    gluster v info myvolume > /dev/null 2>&1
}

mount_gluster_vol() {
    peer_host="$my_base_hostname-0"
    log_message "INFO" "Waiting for peer $peer_host to be ready..."
    
    local max_attempts=30
    local attempt=1
    local delay=10
    
    while [ $attempt -le $max_attempts ]; do
        if peer_ready $peer_host; then
            log_message "INFO" "Peer $peer_host is ready"
            break
        else
            log_message "INFO" "Peer $peer_host not ready yet (Attempt $attempt/$max_attempts)"
            if [ $attempt -lt $max_attempts ]; then
                sleep $delay
            fi
            attempt=$((attempt+1))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_message "WARN" "Peer not ready after $max_attempts attempts, continuing anyway..."
    fi
    
    log_message "INFO" "Waiting for volume to be ready..."
    max_attempts=30
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if volume_ready; then
            log_message "INFO" "Volume is ready"
            break
        else
            log_message "INFO" "Volume not ready yet (Attempt $attempt/$max_attempts)"
            if [ $attempt -lt $max_attempts ]; then
                sleep $delay
            fi
            attempt=$((attempt+1))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_message "WARN" "Volume not ready after $max_attempts attempts, continuing anyway..."
    fi
    
    # Additional wait to ensure volume is fully ready
    sleep 30s
    
    log_message "INFO" "Mounting GlusterFS volume..."
    mkdir -p /gluster-storage
    echo "localhost:/myvolume /gluster-storage glusterfs defaults,_netdev 0 0" >> /etc/fstab
    mount /gluster-storage && df -h
}

# Initialize Docker Swarm or join existing swarm
if [[ $(echo $(hostname) | grep "\-0$") ]]; then
    log_message "INFO" "This is the first node, initializing Docker Swarm..."
    
    # Initialize Docker Swarm with retry
    retry_command "docker swarm init --advertise-addr enp0s3" "Initialize Docker Swarm" 3 10
    
    # Create GlusterFS volume
    create_gluster_vol
else
    if [[ $(echo $(hostname) | grep "\-1$") ]]; then
        log_message "INFO" "This is the second node, joining as manager..."
        mount_gluster_vol
        
        # Wait before joining to ensure first node is ready
        sleep 30s
        
        # Join as manager with retry
        log_message "INFO" "Joining swarm as manager..."
        max_attempts=5
        attempt=1
        delay=10
        
        while [ $attempt -le $max_attempts ]; do
            log_message "INFO" "Attempt $attempt/$max_attempts: Getting join token from manager"
            join_command=$(ssh -o "StrictHostKeyChecking no" root@$my_base_hostname-0 docker swarm join-token manager | tail -2)
            
            if [ -n "$join_command" ]; then
                log_message "INFO" "Executing join command: $join_command"
                eval $join_command
                
                if [ $? -eq 0 ]; then
                    log_message "INFO" "Successfully joined swarm as manager"
                    break
                else
                    log_message "WARN" "Failed to join swarm (Attempt $attempt/$max_attempts)"
                fi
            else
                log_message "WARN" "Failed to get join token (Attempt $attempt/$max_attempts)"
            fi
            
            if [ $attempt -lt $max_attempts ]; then
                log_message "INFO" "Retrying in $delay seconds..."
                sleep $delay
            fi
            attempt=$((attempt+1))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            log_message "ERROR" "Failed to join swarm after $max_attempts attempts"
            exit 1
        fi
    else
        log_message "INFO" "This is a worker node, joining as worker..."
        
        # Wait longer before joining to ensure managers are ready
        sleep 60s
        
        # Join as worker with retry
        log_message "INFO" "Joining swarm as worker..."
        max_attempts=5
        attempt=1
        delay=10
        
        while [ $attempt -le $max_attempts ]; do
            log_message "INFO" "Attempt $attempt/$max_attempts: Getting join token from manager"
            join_command=$(ssh -o "StrictHostKeyChecking no" root@$my_base_hostname-0 docker swarm join-token worker | tail -2)
            
            if [ -n "$join_command" ]; then
                log_message "INFO" "Executing join command: $join_command"
                eval $join_command
                
                if [ $? -eq 0 ]; then
                    log_message "INFO" "Successfully joined swarm as worker"
                    break
                else
                    log_message "WARN" "Failed to join swarm (Attempt $attempt/$max_attempts)"
                fi
            else
                log_message "WARN" "Failed to get join token (Attempt $attempt/$max_attempts)"
            fi
            
            if [ $attempt -lt $max_attempts ]; then
                log_message "INFO" "Retrying in $delay seconds..."
                sleep $delay
            fi
            attempt=$((attempt+1))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            log_message "ERROR" "Failed to join swarm after $max_attempts attempts"
            exit 1
        fi
    fi
fi

# Enable Docker plugins
docker plugin enable glusterfs
docker plugin enable s3fs

# Create overlay networks if this is the manager node
if [[ $(echo $(hostname) | grep "\-0$") ]]; then
    log_message "INFO" "Creating overlay networks..."
    
    # Create lb_network if it doesn't exist
    if ! docker network ls | grep -q "lb_network"; then
        log_message "INFO" "Creating lb_network..."
        retry_command "docker network create --driver=overlay --attachable lb_network" "Create lb_network" 3 5
    else
        log_message "INFO" "lb_network already exists"
    fi
    
    # Create agent_network if it doesn't exist
    if ! docker network ls | grep -q "agent_network"; then
        log_message "INFO" "Creating agent_network..."
        retry_command "docker network create --driver=overlay --attachable agent_network" "Create agent_network" 3 5
    else
        log_message "INFO" "agent_network already exists"
    fi
fi

log_message "INFO" "Finished running improved setup script"
