# Unbound host overrides (Services > Unbound DNS > Overrides).
# Adopted from the live firewall on 2026-11-13; the import blocks below are
# no-ops once applied and can be removed in a follow-up PR.

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

import {
  to = opnsense_unbound_host_override.traefik_wildcard
  id = "b4b73ec8-72b4-4a8e-bfa5-1ad84f64882d"
}

import {
  to = opnsense_unbound_host_override.truenas_wildcard
  id = "3a3fa45b-10b1-4d2a-8b60-1da0f9ac4723"
}
