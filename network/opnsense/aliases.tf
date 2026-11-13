# First managed objects: aliases describing the homelab. They only take
# effect once a rule references them, so creating them is harmless.
# If an alias with the same name already exists in OPNsense, adopt it with an
# import block (imports.tf) instead of letting tofu try to create a duplicate.
#
# Values mirror the rest of the repo:
#   - nodes: kubectl get nodes -o wide
#   - LoadBalancer pool: infra/metallb/config/ip-pool.yaml

resource "opnsense_firewall_alias" "k3s_nodes" {
  name        = "k3s_nodes"
  type        = "host"
  description = "k3s nodes (managed by OpenTofu, homelab repo)"
  content = [
    "10.20.20.2", # k3s-1-master
    "10.20.20.3", # k3s-2-master
    "10.20.20.4", # k3s-3-master
    "10.20.20.5", # k3s-worker-1
    "10.20.20.6", # k3s-worker-2
  ]
}

resource "opnsense_firewall_alias" "k3s_lb_pool" {
  name        = "k3s_lb_pool"
  type        = "host"
  description = "MetalLB LoadBalancer pool (managed by OpenTofu, homelab repo)"
  content     = ["10.20.30.50-10.20.30.200"]
}
