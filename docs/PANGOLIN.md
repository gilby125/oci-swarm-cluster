# Pangolin Service Documentation

## Current Implementation

The current Pangolin service in our Docker Swarm setup is running in "compatibility mode," which is a simplified placeholder rather than the full Pangolin application. This placeholder displays basic information including:

- A message indicating it's running in compatibility mode
- The domain name
- A redacted token

## What is Pangolin?

[Pangolin](https://github.com/fosrl/pangolin) is a self-hosted tunneled reverse proxy server with identity and access control, designed to securely expose private resources on distributed networks. The full application includes:

- Reverse proxy through WireGuard tunnel
- Identity and access management with login functionality
- Dashboard UI for managing sites, users, and roles
- Easy deployment options
- Modular design for extensibility

## Upgrading to Full Pangolin

To upgrade from the compatibility mode to the full Pangolin application, follow these steps:

1. **Backup Current Configuration**:
   ```bash
   ssh -i id_rsa opc@<manager_ip> "sudo cp /root/docker-compose.yml /root/docker-compose.backup.yml"
   ```

2. **Install Pangolin**:
   Follow the installation guide at https://docs.fossorial.io/Getting%20Started/quick-install

3. **Configure Pangolin**:
   - Set up proper authentication
   - Configure tunnels for your services
   - Set up access control rules

4. **Update Docker Swarm Configuration**:
   Replace the compatibility mode container with the proper Pangolin configuration in your docker-compose.yml file.

## Integration with Docker Swarm

When properly integrated with Docker Swarm, Pangolin can provide:

- Secure access to all swarm services through a single entry point
- Identity management for service access
- Tunneled connections to remote resources
- Centralized authentication for all services

## Token Security

The token displayed in the compatibility mode is used for service authentication. In a proper Pangolin setup, this token would be securely stored and not displayed on the web interface. Instead, users would authenticate through the Pangolin login page.

## References

- [Pangolin GitHub Repository](https://github.com/fosrl/pangolin)
- [Pangolin Documentation](https://docs.fossorial.io)
- [Pangolin Installation Guide](https://docs.fossorial.io/Getting%20Started/quick-install)
