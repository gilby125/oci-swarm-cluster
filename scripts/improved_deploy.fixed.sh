#!/bin/bash
# Improved deployment script for Docker Swarm

# Source the improved swarm initialization script
source /root/improved_swarm_init.sh

# Function to get the public and private IPs
get_ips() {
    PUBLIC_IP=$(curl -s http://169.254.169.254/opc/v1/instance/public-ip)
    PRIVATE_IP=$(curl -s http://169.254.169.254/opc/v1/instance/private-ip)
    
    log_message "INFO" "Public IP: $PUBLIC_IP"
    log_message "INFO" "Private IP: $PRIVATE_IP"
}

# Main function
main() {
    log_message "INFO" "Starting Docker Swarm deployment..."
    
    # Get the public and private IPs
    get_ips
    
    # Check if Docker Swarm is already initialized
    if docker info | grep -q "Swarm: active"; then
        log_message "INFO" "Swarm is already initialized."
    else
        # Initialize Docker Swarm
        log_message "INFO" "Initializing Docker Swarm..."
        if ! init_swarm_manager "$PRIVATE_IP"; then
            log_message "ERROR" "Failed to initialize Docker Swarm. Trying with public IP..."
            if ! init_swarm_manager "$PUBLIC_IP"; then
                log_message "ERROR" "Failed to initialize Docker Swarm with both private and public IPs. Exiting."
                exit 1
            fi
        fi
    fi
    
    # Create overlay networks
    log_message "INFO" "Creating overlay networks..."
    if ! create_overlay_networks; then
        log_message "ERROR" "Failed to create overlay networks. Exiting."
        exit 1
    fi
    
    # Set up environment variables
    log_message "INFO" "Setting up environment variables..."
    if ! setup_environment_variables; then
        log_message "ERROR" "Failed to set up environment variables. Exiting."
        exit 1
    fi
    
    # Create Traefik configuration
    log_message "INFO" "Creating Traefik configuration..."
    if ! create_traefik_config; then
        log_message "ERROR" "Failed to create Traefik configuration. Exiting."
        exit 1
    fi
    
    # Deploy the stack
    log_message "INFO" "Deploying the stack..."
    if [ -f "/root/docker-compose.yml" ]; then
        if ! deploy_stack "/root/docker-compose.yml" "swarm"; then
            log_message "ERROR" "Failed to deploy stack. Exiting."
            exit 1
        fi
    else
        log_message "ERROR" "docker-compose.yml not found! Exiting."
        exit 1
    fi
    
    # Check stack status
    log_message "INFO" "Checking stack status..."
    if ! check_stack_status "swarm"; then
        log_message "ERROR" "Stack deployment has issues. Please check manually."
        exit 1
    fi
    
    log_message "INFO" "Deployment completed successfully."
    exit 0
}

# Execute the main function
main
