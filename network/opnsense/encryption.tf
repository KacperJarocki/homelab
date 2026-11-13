# State and plan files hold OPNsense object IDs and, as more resources move
# here, secrets (WireGuard keys, PSKs). The repo is public and plan files are
# passed between jobs as workflow artifacts, so both are always encrypted.
#
# The passphrase is TF_VAR_state_passphrase (Secret arc-runners/opnsense-tofu,
# created by scripts/create-network-iac-secrets.sh). Losing it means losing
# the state: keep a copy in the password manager.
variable "state_passphrase" {
  type      = string
  sensitive = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters."
  }
}

terraform {
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method   = method.aes_gcm.main
      enforced = true
    }

    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}
