# Test Scripts for OCI Swarm Cluster

This directory contains test scripts to verify the OCI Swarm Cluster deployment.

## Available Scripts

- **test_endpoints.sh**: Basic test script to verify DNS resolution, HTTP/HTTPS connectivity, and SSL certificates
- **verify_deployment.sh**: Comprehensive verification script including Docker Swarm services and Cloudflare integration

## Usage

```bash
# Make the scripts executable
chmod +x test_endpoints.sh verify_deployment.sh

# Run the basic tests
./test_endpoints.sh

# Run the comprehensive verification
./verify_deployment.sh
```

## Documentation

For detailed information about the test scripts and troubleshooting tips, see the [TESTING.md](../TESTING.md) file in the root directory.
