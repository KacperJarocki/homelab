# Unbound settings (Services > Unbound DNS: General / Advanced / Blocklist),
# a singleton. Generated from the live firewall on 2026-11-13 so every field
# matches what was there; the only intended change is enable_dnssec.
# Host overrides are in dns.tf.
#
# Never delete this block: un-manage it with
#   removed {
#     from = opnsense_unbound_settings.main
#     lifecycle { destroy = false }
#   }

resource "opnsense_unbound_settings" "main" {
  acls = {
    default_action = "allow"
  }
  advanced = {
    aggressive_nsec = true
    cache = {
      enable_prefetch          = false
      host_ttl                 = -1
      keep_probing_hosts       = false
      max_negative_ttl         = -1
      max_ttl                  = -1
      min_ttl                  = -1
      msg_cache_size           = ""
      num_hosts                = -1
      rrset_cache_size         = ""
      unwanted_reply_threshold = -1
    }
    discard_timeout     = -1
    dnssec_stripped     = false
    enable_prefetch_key = false
    hide_identity       = false
    hide_version        = false
    incoming_num_tcp    = -1
    insecure_domains    = []
    jostle_timeout      = -1
    logging = {
      extended_statistics = true
      log_local_actions   = false
      log_queries         = false
      log_replies         = false
      log_servfail        = false
      tag_query_reply     = false
      validation_level    = 0
      verbosity_level     = 1
    }
    num_queries_per_thread = -1
    outgoing_num_tcp       = -1
    outgoing_range         = -1
    private_addresses      = ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "169.254.0.0/16", "172.16.0.0/12", "192.0.2.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24", "2001:db8::/32", "203.0.113.0/24", "233.252.0.0/24", "::1/128", "fc00::/8", "fd00::/8", "fe80::/10"]
    private_domains        = []
    qname_min_strict       = false
    serve_expired = {
      client_response_timeout = ""
      enabled                 = false
      record_reply_ttl        = ""
      reset_ttl               = false
      ttl                     = ""
    }
  }
  dnsbl = {
    blocklist_domains   = []
    blocklists          = []
    destination_address = ""
    enabled             = false
    force_safe_search   = false
    return_nxdomain     = false
    type                = []
    whitelist_domains   = []
    wildcard_domains    = []
  }
  forwarding = {
    enabled = false
  }
  general = {
    dhcp_domain_override          = ""
    dns64_prefix                  = ""
    enable_dns64                  = false
    enable_dnssec                 = true # was false (2026-11-13)
    enable_reload_cache_flush     = false
    enable_txt_support            = false
    enable_wpad                   = false
    enabled                       = true
    listen_interfaces             = []
    local_zone_type               = "transparent"
    no_a_records                  = false
    outgoing_interfaces           = []
    port                          = 53
    register_dhcp_leases          = false
    register_dhcp_static_mappings = false
    register_ipv6_link_local      = true
    register_systems_records      = true
  }
}

import {
  to = opnsense_unbound_settings.main
  id = "unbound_settings"
}
