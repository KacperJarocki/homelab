# Adopting objects that already exist in OPNsense, without touching them.
#
# What OpenTofu does and does not do:
#   - It only manages objects in its state. Anything not imported or created
#     here is invisible to it and is never changed or deleted.
#   - An import block only reads the object into state. The danger is the
#     resource block next to it: if it differs from the live object, the same
#     apply also *modifies* the object to match the code.
#   - Deleting a resource block later deletes the object. To stop managing an
#     object but keep it, use a `removed` block instead:
#       removed {
#         from = opnsense_firewall_alias.foo
#         lifecycle { destroy = false }
#       }
#   - The workflow refuses any plan with deletes/replaces unless it is
#     dispatched by hand with allow_destroy.
#
# Procedure, one small batch per PR:
#   1. Find the UUIDs (read-only API calls), e.g.
#        curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
#          "$OPNSENSE_URI/api/firewall/alias/search_item" | jq '.rows[] | {uuid, name}'
#        .../api/unbound/settings/search_host_override
#        .../api/kea/dhcpv4/search_reservation
#        .../api/firewall/filter/search_rule
#   2. Add only the import blocks here, no resource blocks.
#   3. Locally (README, "Running locally"):
#        tofu plan -generate-config-out=generated.tf
#      OpenTofu writes resource blocks copied from the live objects.
#   4. Move them into aliases.tf / dns.tf / ..., tidy names, and re-plan until
#      the plan says "N to import, 0 to add, 0 to change, 0 to destroy".
#      Anything other than 0/0/0 means the code does not match reality yet:
#      fix the code, never "let apply sort it out".
#   5. PR -> merge -> approve the apply (it only writes state). Then delete
#      the import blocks in a follow-up PR.
#
# Scope limits of the provider (browningluke/opnsense):
#   - Firewall rules: only the MVC rules (Firewall > Automation / "Rules
#     [new]", API firewall/filter). Classic per-interface rules are not in
#     that API and cannot be imported; if search_rule does not list them,
#     they stay manual until migrated in the GUI.
#   - DHCP: Kea (and dnsmasq) only, not ISC DHCP static mappings.
#   - Interface assignments and system settings are not covered at all.
#
# Inventory of opnsense-1 (26.1.2), 2026-11-13, read-only API survey:
#   - Unbound host overrides: 2 -> imported in dns.tf
#   - Aliases: 11, all system-managed (internal __*_network, bogons,
#     sshlockout, virusprot, __wazuh_agent_drop) -> never manage these
#   - Port forwards: 2, both the auto-generated anti-lockout -> never
#   - Cron: 1, owned by IDS -> never
#   - MVC filter rules, NAT 1:1/source NAT, Kea, dnsmasq hosts, VLANs, VIPs,
#     routes, WireGuard, IPsec, OpenVPN: none
#   - The real filter rules are classic per-interface rules: not reachable
#     through the provider. Bringing them in means recreating them as MVC
#     rules (Firewall > Rules [new]) one interface at a time, in code, then
#     disabling the classic twin by hand.
#
# Suggested order: aliases -> Unbound host overrides -> DHCP reservations ->
# firewall rules (anti-lockout and LAN->GUI/SSH stay manual) -> VLANs.
#
# import {
#   to = opnsense_firewall_alias.example
#   id = "00000000-0000-0000-0000-000000000000"
# }
