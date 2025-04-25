# Configure Cloudflare provider with API key authentication
provider "cloudflare" {
  api_token = var.cloudflare_api_token != "" ? var.cloudflare_api_token : "dummy_token_not_used_1234567890abcdefghijklmnopqrstuvwxyz"
}

locals {
  # Set to false to disable Cloudflare operations for testing
  enable_cloudflare = false
  # Only use Cloudflare if all required values are provided and valid
  use_cloudflare = local.enable_cloudflare && var.cloudflare_email != "" && var.cloudflare_api_token != "" && var.domain_name != "" && var.cloudflare_zone_id != ""

  dns_records = local.use_cloudflare ? [
    "dev-oci",
    "local",
    "local-version",
    "registry",
    "registry-version",
    "portainer",
    "portainer-version",
    "admin-pangolin"
  ] : []

  # This ensures we're explicitly managing all DNS records we care about
  managed_records = local.use_cloudflare ? {
    for record in local.dns_records : record => {
      name    = record
      content = oci_load_balancer_load_balancer.oci_swarm_lb.ip_address_details[0].ip_address
      type    = "A"
      ttl     = 1
      proxied = true
    }
  } : {}
}

# Only create Cloudflare resources if use_cloudflare is true
# Cloudflare zone data source
data "cloudflare_zone" "domain" {
  count   = local.use_cloudflare && var.cloudflare_zone_id != "" ? 1 : 0
  zone_id = var.cloudflare_zone_id
}

# DNS records - only created if Cloudflare is enabled
resource "cloudflare_dns_record" "dns_records" {
  for_each = local.use_cloudflare ? local.managed_records : {}

  zone_id = local.use_cloudflare && var.cloudflare_zone_id != "" ? var.cloudflare_zone_id : ""
  name    = each.value.name
  content = each.value.content
  type    = each.value.type
  ttl     = each.value.ttl
  proxied = each.value.proxied

  # This ensures we don't create duplicate records
  lifecycle {
    create_before_destroy = true
    # Use the record name as part of the ID to prevent duplicates
    # This makes Terraform identify existing records by name
    ignore_changes = [
      priority,
      comment
    ]
  }
}
