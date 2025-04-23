# A Docker Swarm Cluster deployed as terraform scripts

This is a Terraform configuration that deploys a two node Swarm cluster on [Oracle Cloud Infrastructure (OCI)][oci].

It also includes an HA storage implemented in GlusterFS and docker plugins for Gluster FS and Oracle Object Storage.

## Topology

The application uses a typical topology for a 3-tier web application as follows

![OciSwarm Basic Infra](https://miro.medium.com/max/700/1*WDh1kMHnQTg2Ed9orIq7-w.png)

### Components

| Component             | What                                                                                                           | Why                                                                                                                                                                                                                                    | Learn                 |
| --------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| Compute Instances     | 2 Always Free tier eligible compute instance                                                              | These VMs host the application                                                                                                                                                                                                         | [Learn More][inst]    |
| Autonomous Database   | 1 Always Free tier eligible Autonomous Database instance (Optional)                                                      | The database used by the application. Can be disabled at apply time.                                                                                                                                                                                                  | [Learn More][adb]     |
| Vault                 | Optional use of OCI Vault keys for Key Management (KMS).       | Encrypt boot volumes of the compute instances and Object Storage buckets.                                             | [Learn More][kms] |
| Load Balancer         | 1 Always Free tier eligible load balancer                                                                      | Routes traffic between the nodes hosting the application                                                                                                                                                                               | [Learn More][lb]      |
| Virtual Cloud Network | This resource provides a virtual network in the cloud                                                          | The virtual network used by the application to host all its networking components                                                                                                                                                      | [Learn More][vcn]     |
| Private Subnet        | A subnet within the network that does not allow the network components to have publicly reachable IP addresses | The private subnet is used to house the compute instances. Being private, they ensure that the application nodes are not exposed to the internet                                                                                       | [Learn More][vcn]     |
| Public Subnet         | A subnet that allows public IPs.                                                                               | The subnet that houses the public load balancer. Components in this subnet can be allocated public IP addresses and be exposed to the internet through the InternetGateway.                                                            | [Learn More][vcn]     |
| Internet Gateway      | A virtual router that allows direct internet access.                                                           | This enables the load balancer to be reachable from the internet.                                                                                                                                                                      | [Learn More][igw]     |
| NAT Gateway           | (Not available on Always-free only) A virtual router that allows internet access without exposing the source directly to the internet              | It gives the compute instances (with no public IP addresses) access to the internet without exposing them to incoming internet connections.                                                                                            | [Learn More][natgw]   |
| Service Gateway       | (Not available on Always-free only) A virtual router that enables private traffic to OCI services from a VCN                                       | Provides a path for private network traffic between your VCN and services like Object Storage or ATP.                                                                                                                                  | [Learn More][svcgw]   |
| Route Tables          | Route tables route traffic that leaves the VCN.                                                                | The public subnet route rules direct traffic to use the Internet Gateway, while the private subnet route rules enable the compute instances to reach the internet through the NAT gateway and OCI services through the service gateway | [Learn More][rt]      |
| Security Lists        | Security Lists act like a firewall with the rules determining what type of traffic is allowed in or out.       | Security rules enable HTTP traffic to the LoadBalancer from anywhere. Also enables are HTTP and SSH traffic to the compute instances, but only from the subnet where the load balancer is.                                             | [Learn More][seclist] |
| Cloudflare Integration | Integration with Cloudflare for DNS management and SSL certificates | Enables automatic DNS configuration and SSL certificate generation for your domains using Cloudflare | [Learn More][cloudflare] |

## Using local or CloudShell terraform

Clone <https://github.com/marcelo-ochoa/oci-swarm-cluster>

### Setting Up Configuration Files

#### Option 1: Manual Configuration

- Rename the file `terraform.tfvars.example` to `terraform.tfvars`
- Change the credentials variables to your user and any other desirable variables
- Create a `secrets.tfvars` file based on the `secrets.tfvars.example` template
- Add your sensitive variables to `secrets.tfvars`, including:
  - `cloudflare_email` - Your Cloudflare account email
  - `cloudflare_api_token` - Your Cloudflare API token
  - `domain_name` - Your domain managed by Cloudflare

#### Option 2: Using the Setup Script

Run the setup script to create your secrets.tfvars file interactively:

```bash
./setup_secrets.sh
```

This script will guide you through creating a properly formatted secrets.tfvars file with all required variables.

### Deployment Options

- Optionally set `deploy_database=false` or `deploy_web_app=false` to disable those components
- Run `terraform init` to init the terraform providers
- Run `terraform apply -var-file=secrets.tfvars` to create the resources on OCI

## Using Resource Manager GitHub Connector

Just Fork <https://github.com/marcelo-ochoa/oci-swarm-cluster> using your GitHub account and import using OCI Resource Manager. See how it works on this video:

[![](http://img.youtube.com/vi/mnF090QRqO4/0.jpg)](http://www.youtube.com/watch?v=mnF090QRqO4&start=245 "OCI Resource Manager GitHub Integration")

## Deploy as Zip file

Clone <https://github.com/marcelo-ochoa/oci-swarm-cluster>

- Go into directory oci-swarm-cluster and zip it using "zip -r ../oci-swarm-cluster.zip *"
- Upload oci-swarm-cluster.zip on using OCI Resource Manager pane

## Configuration Options

### Optional Components

This stack allows you to selectively deploy components:

- **Database Deployment**: Set `deploy_database=false` to skip deploying the Autonomous Database
- **Web Application Deployment**: Set `deploy_web_app=false` to skip deploying the web application components

These options can be set in your terraform.tfvars file or passed as command-line variables.

### Cloudflare Integration

To enable Cloudflare integration for DNS management and SSL certificates:

1. Set `cloudflare_email` to your Cloudflare account email
2. Set `cloudflare_api_token` to your Cloudflare API token with appropriate permissions
3. Set `domain_name` to your domain managed by Cloudflare

This integration enables automatic DNS configuration and SSL certificate generation for your domain.

#### Automated DNS Management

The deployment includes automated DNS management through Terraform:

1. DNS records for all services are automatically created in Cloudflare
2. SSL certificates are automatically obtained through Let's Encrypt
3. Version-specific subdomains are created for each service (e.g., `v2-11-1.dev-oci.yourdomain.com`)

To set up DNS and certificates in one step, run:

```bash
./setup_dns_and_certs.sh
```

This script will:
1. Verify that your secrets.tfvars file exists and contains the required variables
2. Apply the Terraform configuration with flexible SSL initially
3. Wait for certificate issuance
4. Update the SSL setting to full_strict for maximum security
5. Test connectivity to all configured domains

### Pangolin Integration

Pangolin is used to create a secure tunnel to expose your local services to the internet. The Pangolin token is automatically generated if not provided. If you want to use a specific token:

1. Uncomment the `pangolin_token` line in your terraform.tfvars file
2. Set it to your desired token value

The generated or provided token will be used to authenticate your Pangolin instance with the Pangolin service.

You can access the Pangolin admin interface at `https://admin.pangolin.<your-domain>` using the username `admin` and your Pangolin token as the password.

## Testing Your Deployment

After deploying the infrastructure with Terraform, you can verify that all endpoints are working correctly using the provided test scripts:

- **Basic Test Script**: `tests/test_endpoints.sh` - Performs basic tests to verify DNS resolution, HTTP/HTTPS connectivity, and SSL certificates
- **Comprehensive Verification Script**: `tests/verify_deployment.sh` - Provides a more thorough verification including Docker Swarm services and Cloudflare integration

To run the tests:

```bash
# Make the scripts executable
chmod +x tests/test_endpoints.sh tests/verify_deployment.sh

# Basic tests
./tests/test_endpoints.sh

# Comprehensive verification
./tests/verify_deployment.sh
```

The test scripts will automatically check for the existence of your secrets.tfvars file and use values from it if available.

See [TESTING.md](TESTING.md) for detailed information about the test scripts and troubleshooting tips.

## Troubleshooting

If you encounter issues with your Docker Swarm cluster deployment, refer to the [DEBUGGING.md](DEBUGGING.md) guide for a comprehensive approach to identifying and resolving common problems.

The debugging guide covers:

- Traefik configuration issues
- Registry service connectivity
- Cloudflare DNS and routing
- Load balancer configuration
- Docker Swarm network configuration
- Security group and firewall rules
- Pangolin configuration
- Service health checks

The guide provides step-by-step instructions for diagnosing and fixing each type of issue.

[oci]: https://cloud.oracle.com/en_US/cloud-infrastructure
[orm]: https://docs.cloud.oracle.com/iaas/Content/ResourceManager/Concepts/resourcemanager.htm
[tf]: https://www.terraform.io
[net]: https://docs.cloud.oracle.com/iaas/Content/Network/Concepts/overview.htm
[vcn]: https://docs.cloud.oracle.com/iaas/Content/Network/Tasks/managingVCNs.htm
[lb]: https://docs.cloud.oracle.com/iaas/Content/Balance/Concepts/balanceoverview.htm
[igw]: https://docs.cloud.oracle.com/iaas/Content/Network/Tasks/managingIGs.htm
[natgw]: https://docs.cloud.oracle.com/iaas/Content/Network/Tasks/NATgateway.htm
[svcgw]: https://docs.cloud.oracle.com/iaas/Content/Network/Tasks/servicegateway.htm
[rt]: https://docs.cloud.oracle.com/iaas/Content/Network/Tasks/managingroutetables.htm
[seclist]: https://docs.cloud.oracle.com/iaas/Content/Network/Concepts/securitylists.htm
[adb]: https://docs.cloud.oracle.com/iaas/Content/Database/Concepts/adboverview.htm
[inst]: https://docs.cloud.oracle.com/iaas/Content/Compute/Concepts/computeoverview.htm
[kms]: https://docs.cloud.oracle.com/en-us/iaas/Content/KeyManagement/Concepts/keyoverview.htm
[cloudflare]: https://developers.cloudflare.com/fundamentals/get-started/
[magic_button]: https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg
[magic_oci_swarm_basic_stack]: https://console.us-ashburn-1.oraclecloud.com/resourcemanager/stacks/create?region=home&zipUrl=https://github.com/oracle-quickstart/oci-cloudnative/releases/latest/download/oci-swarm-basic-stack-latest.zip
