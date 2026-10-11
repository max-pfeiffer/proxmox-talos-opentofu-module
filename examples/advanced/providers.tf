terraform {
  required_version = ">= 1.11.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
  }
}

provider "proxmox" {
  # bpg/proxmox expects the plain endpoint without the /api2/json path
  endpoint  = trimsuffix(var.proxmox_api_url, "/api2/json")
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_insecure
}

# Only renders the Cilium manifest inside the module and never connects to a cluster. A separate provider keeps the
# module working if a default helm provider is configured with the module's kubernetes_client_configuration output.
provider "helm" {
  alias = "render"
}
