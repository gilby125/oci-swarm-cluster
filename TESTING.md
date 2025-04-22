# Testing Your OCI Swarm Cluster Deployment

This document provides detailed information about the test scripts included in this repository and how to use them to verify your OCI Swarm Cluster deployment.

## Overview

After deploying the infrastructure with Terraform, it's important to verify that all components are working correctly. The test scripts in this repository help you verify:

- DNS resolution for all subdomains
- HTTP/HTTPS connectivity to all endpoints
- SSL certificate validation
- Docker Swarm services
- Cloudflare integration
- Pangolin functionality

## Available Test Scripts

### 1. Basic Test Script: `tests/test_endpoints.sh`

This script performs basic tests to verify that the deployment is working correctly:

- **DNS Resolution Tests**: Checks if the subdomains (dev-oci, registry, local) resolve to the correct IP addresses
- **HTTP Connectivity Tests**: Verifies that the load balancer and whoami endpoint are accessible
- **HTTPS Connectivity Tests**: Checks if the Portainer UI, Registry, and Local Proxy are accessible
- **HTTPS Certificate Tests**: Validates the SSL certificates for the subdomains

#### Usage:

```bash
./tests/test_endpoints.sh
```

### 2. Comprehensive Verification Script: `tests/verify_deployment.sh`

This script provides a more comprehensive verification of the deployment:

- **Terraform Output Retrieval**: Gets the domain name, load balancer IP, and Pangolin token from Terraform output
- **DNS Resolution Tests**: Checks if the subdomains resolve to the correct IP addresses
- **HTTP/HTTPS Connectivity Tests**: Verifies that all endpoints are accessible
- **SSH Connectivity Tests**: Checks if the compute instances are accessible via SSH (optional)
- **Docker Swarm Services Tests**: Verifies that the Docker Swarm services are running correctly (optional)
- **Cloudflare Integration Tests**: Checks if the domain is using Cloudflare

#### Usage:

```bash
./tests/verify_deployment.sh
```

## When to Run These Scripts

Run these scripts after the Terraform apply has completed and the infrastructure has been provisioned. It's recommended to wait a few minutes after the apply completes to allow the services to start up and DNS to propagate.

## Prerequisites

The test scripts require the following tools:

- `bash` - The scripts are written in Bash
- `curl` or `wget` - For HTTP/HTTPS connectivity tests
- `dig` or `nslookup` - For DNS resolution tests
- `openssl` - For SSL certificate validation
- `ssh` - For SSH connectivity tests (optional)

Most Linux and macOS systems have these tools installed by default. On Windows, you can use WSL (Windows Subsystem for Linux) or Git Bash.

## Troubleshooting

If the tests fail, here are some common issues and how to resolve them:

### DNS Resolution Failures

- **Issue**: The subdomains don't resolve to the correct IP addresses
- **Possible Causes**:
  - DNS propagation is still in progress (can take up to 24 hours)
  - Cloudflare integration is not properly configured
  - The domain name is incorrect
- **Resolution**:
  - Wait for DNS propagation to complete
  - Check your Cloudflare configuration
  - Verify that the domain name is correct in your terraform.tfvars file

### HTTP/HTTPS Connectivity Failures

- **Issue**: The endpoints are not accessible
- **Possible Causes**:
  - The services are still starting up
  - The load balancer is not properly configured
  - The security lists are not properly configured
- **Resolution**:
  - Wait a few minutes for the services to start up
  - Check the load balancer configuration
  - Verify that the security lists allow traffic to the endpoints

### SSL Certificate Validation Failures

- **Issue**: The SSL certificates are not valid
- **Possible Causes**:
  - The certificates are still being issued
  - Cloudflare integration is not properly configured
- **Resolution**:
  - Wait for the certificates to be issued (can take a few minutes)
  - Check your Cloudflare configuration

### Docker Swarm Services Failures

- **Issue**: The Docker Swarm services are not running correctly
- **Possible Causes**:
  - The services are still starting up
  - There was an error during deployment
- **Resolution**:
  - Wait a few minutes for the services to start up
  - SSH into the compute instances and check the Docker logs:
    ```bash
    docker logs $(docker ps -q -f name=pangolin)
    docker logs $(docker ps -q -f name=traefik)
    ```

## Accessing the Pangolin Admin Interface

Pangolin provides an admin interface that allows you to manage your tunnels and view statistics. To access it:

### Method 1: Direct Access via Subdomain

The Pangolin admin interface should be accessible at:

```
https://admin.pangolin.<your-domain>
```

For example:

```
https://admin.pangolin.throughfire.net
```

### Method 2: Access via the Pangolin Container

If the admin interface isn't accessible via the subdomain, you can access it directly through the Pangolin container:

1. SSH into one of your compute instances:
   ```bash
   ssh -i /path/to/private/key opc@<instance-ip>
   ```

2. Find the Pangolin container ID:
   ```bash
   docker ps | grep pangolin
   ```

3. Get the Pangolin container's IP address:
   ```bash
   docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container-id>
   ```

4. Access the admin interface using the container's IP address:
   ```bash
   curl http://<container-ip>:8080
   ```

### Authentication

To access the Pangolin admin interface, you'll need to authenticate using:

- **Username**: admin
- **Password**: Your Pangolin token

You can retrieve the generated token using:

```bash
terraform output pangolin_token
```

## Advanced Testing

For more advanced testing, you can SSH into the compute instances and check the Docker logs directly:

```bash
# SSH into the compute instance
ssh -i /path/to/private/key opc@<instance-ip>

# Check the Docker Swarm services
docker service ls

# Check the Pangolin container logs
docker logs $(docker ps -q -f name=pangolin)

# Check the Traefik container logs
docker logs $(docker ps -q -f name=traefik)

# Check the Docker Compose file
cat /root/docker-compose.processed.yml
```

## Customizing the Tests

You can customize the test scripts to suit your specific needs:

- **Adding New Tests**: Add new test functions to the scripts
- **Changing Timeouts**: Modify the timeout values in the scripts
- **Testing Different Endpoints**: Add or remove endpoints to test

## Continuous Integration

These test scripts can be integrated into your CI/CD pipeline to automatically verify your deployments:

```yaml
# Example GitHub Actions workflow
name: Test Deployment

on:
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v2

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v1

      - name: Run tests
        run: |
          chmod +x tests/test_endpoints.sh
          ./tests/test_endpoints.sh
```

## Conclusion

The test scripts provided in this repository help you verify that your OCI Swarm Cluster deployment is working correctly. By running these scripts after deployment, you can ensure that all components are functioning as expected and troubleshoot any issues that may arise.
