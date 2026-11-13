terraform {
  required_version = ">= 1.10.0"

  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.26.0"
    }
  }

  # State lives in the in-cluster RustFS (infra/rustfs), bucket created by the
  # rustfs-buckets Job. The endpoint and credentials come from the environment
  # so the same config works from the runner (cluster DNS) and from a laptop
  # (kubectl port-forward), see README.md:
  #   AWS_ENDPOINT_URL_S3, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  backend "s3" {
    bucket = "tofu-state"
    key    = "network/opnsense/terraform.tfstate"
    region = "us-east-1"

    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
