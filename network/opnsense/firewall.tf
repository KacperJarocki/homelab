# Filter rules (Firewall > Rules [new]), migrated from the classic rules with
# the Migration assistant and adopted on 2026-11-13.
#
# Interfaces: lan = LAN 10.10.0.0/16, opt3 = PRD 10.20.0.0/16 (k3s nodes,
# MetalLB pool, the firewall itself at 10.20.0.1).
#
# `sequence` is the evaluation order; keep gaps of 10 for inserts.
#
# Deliberately NOT managed here (lockout protection, change in the GUI only):
#   - the automatic anti-lockout rules
#   - "FW GUI" (PRD -> firewall, uuid 497eff7a-...), sequence 41: it is how
#     the in-cluster runner reaches this API. Keep 41 free in this file.

# --- LAN ---------------------------------------------------------------------

resource "opnsense_firewall_filter" "lan_to_prd" {
  description = "Allow lan to prd"
  sequence    = 1
  interface   = { interface = ["lan"] }
  filter = {
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet"
    protocol    = "any"
    source      = { net = "lan" }
    destination = { net = "opt3" }
    log         = true
  }
}

resource "opnsense_firewall_filter" "lan_to_any_v4" {
  description = "Default allow LAN to any rule"
  sequence    = 11
  interface   = { interface = ["lan"] }
  filter = {
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet"
    protocol    = "any"
    source      = { net = "lan" }
    destination = { net = "any" }
  }
}

resource "opnsense_firewall_filter" "lan_to_any_v6" {
  description = "Default allow LAN IPv6 to any rule"
  sequence    = 21
  interface   = { interface = ["lan"] }
  filter = {
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet6"
    protocol    = "any"
    source      = { net = "lan" }
    destination = { net = "any" }
  }
}

# --- PRD (opt3) --------------------------------------------------------------

# PRD may not initiate anything towards LAN (LAN -> PRD is allowed above).
resource "opnsense_firewall_filter" "prd_block_lan" {
  sequence  = 31
  interface = { interface = ["opt3"] }
  filter = {
    action      = "block"
    direction   = "in"
    ip_protocol = "inet"
    protocol    = "any"
    source      = { net = "opt3" }
    destination = { net = "lan" }
    log         = true
  }
}

resource "opnsense_firewall_filter" "prd_to_prd" {
  sequence  = 51
  interface = { interface = ["opt3"] }
  filter = {
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet"
    protocol    = "any"
    source      = { net = "opt3" }
    destination = { net = "opt3" }
  }
}

resource "opnsense_firewall_filter" "prd_to_any" {
  sequence  = 61
  interface = { interface = ["opt3"] }
  filter = {
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet"
    protocol    = "any"
    source      = { net = "opt3" }
    destination = { net = "any" }
  }
}

import {
  to = opnsense_firewall_filter.lan_to_prd
  id = "439eb4c0-2a30-4c63-9429-a363f0300a5b"
}

import {
  to = opnsense_firewall_filter.lan_to_any_v4
  id = "326bb406-c4ba-4e85-8e74-9c8212dcce7d"
}

import {
  to = opnsense_firewall_filter.lan_to_any_v6
  id = "895ba6e8-0877-4b06-ab11-5882f86091a0"
}

import {
  to = opnsense_firewall_filter.prd_block_lan
  id = "0143fffe-02d2-45cb-b02f-fbf69b096dc4"
}

import {
  to = opnsense_firewall_filter.prd_to_prd
  id = "9acb60ca-8d75-4980-9f05-e65d13efc700"
}

import {
  to = opnsense_firewall_filter.prd_to_any
  id = "6e434209-849f-49c9-b128-153a0c5f3ef3"
}
