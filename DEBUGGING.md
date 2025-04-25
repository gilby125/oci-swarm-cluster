# Docker Swarm Cluster Debugging Guide

This guide provides a comprehensive approach to debugging issues with the OCI Docker Swarm cluster deployment. Use this document when troubleshooting connectivity, service, or configuration problems.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Traefik Configuration Issues](#traefik-configuration-issues)
3. [Registry Service Connectivity](#registry-service-connectivity)
4. [Cloudflare DNS and Routing](#cloudflare-dns-and-routing)
5. [Load Balancer Configuration](#load-balancer-configuration)
6. [Docker Swarm Network Configuration](#docker-swarm-network-configuration)
7. [Security Group and Firewall Rules](#security-group-and-firewall-rules)
8. [Pangolin Configuration](#pangolin-configuration)
9. [Service Health Checks](#service-health-checks)
10. [Common Issues and Solutions](#common-issues-and-solutions)

## Prerequisites

Before starting the debugging process, ensure you have:

- SSH access to the compute instances
- The private key file used for deployment
- Access to the Cloudflare account managing your domain
- The Terraform state file (if available)

## Traefik Configuration Issues

### Problem Identification

- Inconsistent certresolver naming between services and Traefik configuration
- Environment variable substitution issues in the Docker Compose file
- Incorrect routing rules for services

### Debugging Steps

1. **Check Traefik service configuration:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker service inspect swarm_traefik"
```

2. **Examine Traefik logs:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker logs \$(sudo docker ps -q -f name=swarm_traefik)"
```

3. **Verify environment variable substitution:**

```bash
ssh -i private_key.pem opc@<instance-ip> "cat /root/docker-compose.processed.yml"
```

### Solutions

1. Ensure consistent certresolver naming across all services:

```yaml
# In all service labels
- traefik.http.routers.service-name.tls.certresolver=cloudflare
```

2. Fix environment variable substitution by using `envsubst` before deployment:

```bash
envsubst < docker-compose.template.yml > docker-compose.processed.yml
```

3. Update the Docker Compose file with correct routing rules for each service.

## Registry Service Connectivity

### Problem Identification

- Registry service not properly exposed on the overlay network
- Inconsistent routing rules for the registry service
- Port 5000 not accessible

### Debugging Steps

1. **Check registry service configuration:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker service inspect swarm_registry"
```

2. **Examine registry logs:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker logs \$(sudo docker ps -q -f name=swarm_registry)"
```

3. **Test registry connectivity from within the swarm:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker exec -it \$(sudo docker ps -q -f name=swarm_traefik) curl -I registry:5000/v2/"
```

### Solutions

1. Ensure the registry service is properly connected to the `lb_network`:

```yaml
registry:
    networks:
        - lb_network
```

2. Update the registry service configuration with consistent routing rules:

```yaml
labels:
    - traefik.enable=true
    - traefik.docker.network=lb_network
    - traefik.constraint-label=traefik-public
    - traefik.http.routers.registry.rule=(Host(`registry.${domain_name}`) && PathPrefix(`/v2/`))
    - traefik.http.routers.registry.entrypoints=https
    - traefik.http.routers.registry.tls=true
    - traefik.http.routers.registry.tls.certresolver=cloudflare
    - traefik.http.services.registry.loadbalancer.server.port=5000
```

3. Verify port 5000 is exposed and accessible:

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo netstat -tulpn | grep 5000"
```

## Cloudflare DNS and Routing

### Problem Identification

- Cloudflare DNS records not properly configured
- SSL/TLS settings incorrect (flexible vs full_strict)
- Cloudflare API token missing necessary permissions

### Debugging Steps

1. **Verify Cloudflare DNS records:**

```bash
# Using the Cloudflare API
curl -X GET "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records" \
     -H "Authorization: Bearer <api-token>" \
     -H "Content-Type: application/json"
```

2. **Check SSL/TLS settings:**

```bash
# Using the Cloudflare API
curl -X GET "https://api.cloudflare.com/client/v4/zones/<zone-id>/settings/ssl" \
     -H "Authorization: Bearer <api-token>" \
     -H "Content-Type: application/json"
```

3. **Test direct IP access vs. domain access:**

```bash
curl -I http://<load-balancer-ip>/whoami
curl -I https://dev-oci.<domain-name>/whoami
```

### Solutions

1. Use the `setup_dns_and_certs.sh` script to properly configure DNS and SSL/TLS settings:

```bash
./setup_dns_and_certs.sh
```

2. Ensure the Cloudflare API token has the necessary permissions:
   - Zone.DNS (Edit)
   - Zone.SSL and Certificates (Edit)

3. Manually update Cloudflare DNS records if needed:

```bash
terraform apply -var-file=secrets.tfvars -target=cloudflare_record.dev_oci
```

## Load Balancer Configuration

### Problem Identification

- Load balancer health checks failing
- Backend set configuration incorrect
- Ports not properly configured

### Debugging Steps

1. **Check load balancer health status:**

```bash
# Using OCI CLI
oci lb load-balancer get --load-balancer-id <lb-id>
```

2. **Verify backend set configuration:**

```bash
# Using OCI CLI
oci lb backend-set get --backend-set-name <backend-set-name> --load-balancer-id <lb-id>
```

3. **Test direct access to the load balancer IP:**

```bash
curl -I http://<load-balancer-ip>/whoami
```

### Solutions

1. Update the load balancer health check configuration:

```hcl
health_checker {
  port                = "80"
  protocol            = "HTTP"
  response_body_regex = ".*"
  url_path            = "/whoami"
  return_code         = 200
  interval_ms         = 5000
  timeout_in_millis   = 2000
  retries             = 10
}
```

2. Ensure all necessary ports are open on the load balancer (80, 443):

```hcl
resource "oci_load_balancer_listener" "oci_swarm_listener_80" {
  load_balancer_id         = oci_load_balancer_load_balancer.oci_swarm_lb.id
  default_backend_set_name = oci_load_balancer_backend_set.oci_swarm_bes.name
  name                     = "oci-swarm-${random_string.deploy_id.result}-80"
  port                     = 80
  protocol                 = "TCP"
}

resource "oci_load_balancer_listener" "oci_swarm_listener_443" {
  load_balancer_id         = oci_load_balancer_load_balancer.oci_swarm_lb.id
  default_backend_set_name = oci_load_balancer_backend_set.oci_swarm_bes_ssl.name
  name                     = "oci-swarm-${random_string.deploy_id.result}-443"
  port                     = 443
  protocol                 = "TCP"
}
```

## Docker Swarm Network Configuration

### Problem Identification

- Overlay networks not properly created
- Services not attached to the correct networks
- Network connectivity issues between services

### Debugging Steps

1. **Verify overlay networks:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker network ls"
ssh -i private_key.pem opc@<instance-ip> "sudo docker network inspect lb_network"
ssh -i private_key.pem opc@<instance-ip> "sudo docker network inspect agent_network"
```

2. **Check service network attachments:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker service inspect swarm_registry --format '{{.Spec.TaskTemplate.Networks}}'"
```

3. **Test network connectivity between services:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker exec -it \$(sudo docker ps -q -f name=swarm_traefik) ping -c 3 registry"
```

### Solutions

1. Recreate overlay networks if needed:

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker network create -d overlay lb_network"
ssh -i private_key.pem opc@<instance-ip> "sudo docker network create -d overlay agent_network"
```

2. Update service definitions to attach to the correct networks:

```yaml
services:
  service_name:
    networks:
      - lb_network
      - agent_network  # if needed
```

3. Redeploy the stack with updated network configurations:

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker stack deploy -c /root/docker-compose.processed.yml swarm"
```

## Security Group and Firewall Rules

### Problem Identification

- Security group rules too restrictive
- Firewall rules on instances blocking traffic
- Missing ports for Docker Swarm communication

### Debugging Steps

1. **Check security group rules:**

```bash
# Using OCI CLI
oci network security-list get --security-list-id <security-list-id>
```

2. **Verify firewall rules on instances:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo firewall-cmd --list-all"
```

3. **Test connectivity on specific ports:**

```bash
# From another machine
nc -zv <instance-ip> 80
nc -zv <instance-ip> 443
nc -zv <instance-ip> 2377
```

### Solutions

1. Update security group rules to allow necessary traffic:

```hcl
ingress_security_rules {
  protocol = local.tcp_protocol_number
  source   = lookup(var.network_cidrs, "ALL-CIDR")

  tcp_options {
    max = local.http_port_number
    min = local.http_port_number
  }
}
```

2. Configure firewall rules on instances:

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo firewall-cmd --permanent --add-port=80/tcp"
ssh -i private_key.pem opc@<instance-ip> "sudo firewall-cmd --permanent --add-port=443/tcp"
ssh -i private_key.pem opc@<instance-ip> "sudo firewall-cmd --permanent --add-port=2377/tcp"
ssh -i private_key.pem opc@<instance-ip> "sudo firewall-cmd --permanent --add-port=7946/tcp"
ssh -i private_key.pem opc@<instance-ip> "sudo firewall-cmd --permanent --add-port=7946/udp"
ssh -i private_key.pem opc@<instance-ip> "sudo firewall-cmd --permanent --add-port=4789/udp"
ssh -i private_key.pem opc@<instance-ip> "sudo firewall-cmd --reload"
```

## Pangolin Configuration

### Problem Identification

- Pangolin token not properly configured
- Pangolin service not properly connected to the network
- DNS records for Pangolin admin interface missing

### Debugging Steps

1. **Verify Pangolin token:**

```bash
ssh -i private_key.pem opc@<instance-ip> "grep PANGOLIN_TOKEN /root/swarm.env"
```

2. **Check Pangolin service logs:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker logs \$(sudo docker ps -q -f name=swarm_pangolin)"
```

3. **Test connectivity to Pangolin admin interface:**

```bash
curl -I https://admin.pangolin.<domain-name>
```

### Solutions

1. Ensure the Pangolin token is correctly generated and passed to the service:

```hcl
pangolin_token = var.pangolin_token != "" ? var.pangolin_token : random_string.pangolin_token.result
```

2. Update the Pangolin service configuration:

```yaml
pangolin:
    image: ghcr.io/dperson/pangolin:latest
    restart: unless-stopped
    environment:
        - TOKEN=${pangolin_token}
        - DOMAIN=${domain_name}
    networks:
        - lb_network
```

3. Verify the DNS record for the Pangolin admin interface:

```hcl
resource "cloudflare_record" "admin_pangolin" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "admin.pangolin"
  content = oci_core_instance.app_instance[0].public_ip
  type    = "A"
  proxied = true
}
```

## Service Health Checks

### Problem Identification

- Services not healthy or running
- Resource constraints affecting service deployment
- Service configuration issues

### Debugging Steps

1. **Check service status:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker service ls"
```

2. **Verify service placement:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker service ps --no-trunc swarm_traefik"
ssh -i private_key.pem opc@<instance-ip> "sudo docker service ps --no-trunc swarm_portainer"
ssh -i private_key.pem opc@<instance-ip> "sudo docker service ps --no-trunc swarm_registry"
```

3. **Check for resource constraints:**

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker info"
ssh -i private_key.pem opc@<instance-ip> "free -h"
ssh -i private_key.pem opc@<instance-ip> "df -h"
```

### Solutions

1. Restart services if needed:

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker service update --force swarm_traefik"
```

2. Scale services appropriately:

```bash
ssh -i private_key.pem opc@<instance-ip> "sudo docker service scale swarm_registry=1"
```

3. Address resource constraints by adjusting instance size or scaling down services.

## Common Issues and Solutions

### 1. Certificate Issues

**Problem:** Services are accessible via HTTP but not HTTPS due to certificate issues.

**Solution:**
- Verify Traefik is using the correct certresolver
- Check Cloudflare SSL/TLS settings (should be Full Strict after certificates are issued)
- Ensure the Cloudflare API token has the necessary permissions
- Check Traefik logs for certificate issuance errors

### 2. Service Discovery Issues

**Problem:** Services cannot communicate with each other by name.

**Solution:**
- Verify all services are on the same overlay network
- Check DNS resolution within containers
- Ensure service names are correctly referenced (e.g., `registry` vs `swarm_registry`)

### 3. Load Balancer Health Check Failures

**Problem:** Load balancer reports backends as unhealthy.

**Solution:**
- Verify the health check endpoint is accessible
- Check if the health check path is correctly configured
- Ensure the backend instance is listening on the correct port
- Verify firewall rules allow traffic from the load balancer to the backend

### 4. Duplicate DNS Records

**Problem:** Multiple DNS records exist for the same subdomain, pointing to different IP addresses, causing inconsistent behavior or Cloudflare 520 errors.

**Solution:**
- Use the provided cleanup script to remove duplicate DNS records:
  ```bash
  # Set your Cloudflare credentials as environment variables
  export CLOUDFLARE_API_TOKEN="your_api_token"
  export CLOUDFLARE_ZONE_ID="your_zone_id"

  # Run the cleanup script
  ./scripts/cleanup_dns.sh
  ```
- Verify DNS records are correctly configured:
  ```bash
  # Check DNS records for a specific subdomain
  dig @8.8.8.8 portainer.yourdomain.com
  ```
- Ensure the Terraform configuration uses `allow_overwrite = true` for DNS records
- Use the `lifecycle { create_before_destroy = true }` directive in the Terraform configuration for DNS records
- Check the health check configuration (port, path, protocol)
- Ensure the health check endpoint returns the expected status code

### 4. Portainer Access Issues

**Problem:** Cannot access Portainer UI.

**Solution:**
- Verify Portainer service is running
- Check Traefik routing rules for Portainer
- Ensure Portainer is connected to both `agent_network` and `lb_network`
- Verify the Portainer agent is running on all nodes

### 5. Registry Push/Pull Issues

**Problem:** Cannot push or pull images from the registry.

**Solution:**
- Verify registry service is running
- Check registry logs for errors
- Ensure registry is accessible via HTTPS with valid certificates
- Verify authentication configuration if using authentication

### 6. Pangolin Tunnel Issues

**Problem:** Pangolin tunnel not working.

**Solution:**
- Verify Pangolin service is running
- Check Pangolin logs for connection errors
- Ensure the Pangolin token is correctly configured
- Verify DNS records for Pangolin admin interface

## Conclusion

This debugging guide provides a systematic approach to identifying and resolving issues with your Docker Swarm cluster deployment. By following these steps, you should be able to troubleshoot most common problems and ensure your services are running correctly.

Remember to always check logs first, as they often contain valuable information about what's going wrong. If you're still having issues after following this guide, consider reaching out to the community or consulting the official documentation for the specific components involved.
