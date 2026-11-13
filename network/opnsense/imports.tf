# Adopting objects that already exist in OPNsense, one at a time:
#
#   1. Find the object's UUID: GUI edit URL, or the API, e.g.
#        curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
#          "$OPNSENSE_URI/api/unbound/settings/search_host_override" | jq
#   2. Add an import block here and a matching resource in the right file.
#   3. Let `tofu plan -generate-config-out=generated.tf` draft the resource,
#      move it into place, and iterate until the plan shows "1 to import,
#      0 to add, 0 to change, 0 to destroy".
#   4. After the apply the import block is a no-op; delete it.
#
# Suggested order: aliases -> Unbound host overrides -> Kea reservations ->
# firewall rules (only with the anti-lockout rule left out of tofu) -> VLANs.
#
# import {
#   to = opnsense_unbound_host_override.argocd
#   id = "00000000-0000-0000-0000-000000000000"
# }
