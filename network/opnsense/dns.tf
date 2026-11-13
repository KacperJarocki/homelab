# Unbound host overrides (Services > Unbound DNS > Overrides).
# Adopted from the live firewall on 2026-11-13 (imported by the first apply).

# Everything under homelab.kacperjarocki.dev -> Traefik's LoadBalancer IP
# (first address of the MetalLB pool, infra/metallb/config/ip-pool.yaml).
resource "opnsense_unbound_host_override" "traefik_wildcard" {
  description = "traefik wildcard"
  hostname    = "*"
  domain      = "homelab.kacperjarocki.dev"
  type        = "A"
  server      = "10.20.30.50"
}

# Everything else under kacperjarocki.dev -> TrueNAS.
resource "opnsense_unbound_host_override" "truenas_wildcard" {
  description = "truenas wildcard"
  hostname    = "*"
  domain      = "kacperjarocki.dev"
  type        = "A"
  server      = "10.20.30.1"
}
