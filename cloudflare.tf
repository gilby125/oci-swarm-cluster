terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Get the zone ID for the domain
data "cloudflare_zone" "domain" {
  name = var.domain_name
}

# Create DNS records for the main services
resource "cloudflare_record" "dev_oci" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "dev-oci"
  content = oci_load_balancer_load_balancer.oci_swarm_lb.ip_address_details[0].ip_address
  type    = "A"
  proxied = true
}

resource "cloudflare_record" "registry" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "registry"
  content = oci_load_balancer_load_balancer.oci_swarm_lb.ip_address_details[0].ip_address
  type    = "A"
  proxied = true
}

resource "cloudflare_record" "local" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "local"
  content = oci_load_balancer_load_balancer.oci_swarm_lb.ip_address_details[0].ip_address
  type    = "A"
  proxied = true
}

resource "cloudflare_record" "admin_pangolin" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "admin.pangolin"
  content = oci_core_instance.app_instance[0].public_ip
  type    = "A"
  proxied = true
}

# Create DNS records for version-specific subdomains
resource "cloudflare_record" "portainer_version" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "v2-11-1.dev-oci"
  content = oci_load_balancer_load_balancer.oci_swarm_lb.ip_address_details[0].ip_address
  type    = "A"
  proxied = true
}

resource "cloudflare_record" "registry_version" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "v2.registry"
  content = oci_load_balancer_load_balancer.oci_swarm_lb.ip_address_details[0].ip_address
  type    = "A"
  proxied = true
}

resource "cloudflare_record" "local_version" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "alpine.local"
  content = oci_load_balancer_load_balancer.oci_swarm_lb.ip_address_details[0].ip_address
  type    = "A"
  proxied = true
}

# SSL and HTTPS settings are configured manually or via setup_dns_and_certs.sh script

# SSL settings are configured manually or via setup_dns_and_certs.sh script
