# Providers are configured by the calling root module, see examples/.
# The ephemeral talos_cluster_kubeconfig resource and the write-only kubeconfig_wo
# attribute of talos_machine require OpenTofu >= 1.11.
#
# Pre-1.0 providers ship breaking changes in minor releases, so they are constrained to a
# single minor version and widened by Renovate once CI validated the new release.
#
# release-please rewrites every v-prefixed semantic version in this file with the module
# version, so do not mention any in comments here.
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.119.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }
  }
}
