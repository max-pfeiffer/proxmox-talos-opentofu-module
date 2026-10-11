# Proxmox
variable "proxmox_target_node" {
  description = "Name of the Proxmox VE node the virtual machines are created on. Can be overridden per node with `proxmox_node` in `node_data`."
  type        = string
}

variable "proxmox_storage_device" {
  description = "Proxmox datastore for the virtual machine disks and the cloud-init drives"
  type        = string
}

variable "proxmox_iso_datastore" {
  description = "Proxmox datastore the Talos Linux ISO image is downloaded to, it must support the `iso` content type"
  type        = string
  default     = "local"
}

variable "proxmox_network_bridge" {
  description = "Proxmox network bridge the virtual machines are attached to"
  type        = string
  default     = "vmbr0"
}

variable "vm_cpu_type" {
  description = "CPU type emulated for the virtual machines"
  type        = string
  default     = "host"
}

# Talos Linux
variable "talos_version" {
  description = "Talos machine configuration contract version. Pin it to the version the cluster was created with, it is independent of the installed Talos version which is driven by `install_image`. Required so that a module upgrade never changes the contract of an existing cluster. At least 1.12 is required for the HostnameConfig document."
  type        = string

  validation {
    condition = try(
      tonumber(regex("^v?(\\d+)\\.(\\d+)", var.talos_version)[0]) > 1 ||
      tonumber(regex("^v?(\\d+)\\.(\\d+)", var.talos_version)[1]) >= 12,
      false
    )
    error_message = "talos_version must be 1.12 or newer, the module configures hostnames with the HostnameConfig document."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version of the cluster, changing it runs Talos' upgrade-k8s procedure. Required so that a module upgrade never upgrades Kubernetes implicitly."
  type        = string
}

variable "talos_linux_iso_image_url" {
  description = "URL of the Talos ISO image for initially booting the VM"
  type        = string
  default     = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.13.8/nocloud-amd64.iso"
}

variable "talos_linux_iso_image_filename" {
  description = "Filename of the Talos ISO image for initially booting the VM"
  type        = string
  default     = "talos-linux-v1.13.8-qemu-guest-agent-amd64.iso"
}

variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
  default     = "talos"
}

variable "cluster_vip_shared_ip" {
  description = "Shared virtual IP address for control plane nodes, used as Kubernetes API endpoint"
  type        = string

  validation {
    condition     = can(cidrhost("${var.cluster_vip_shared_ip}/32", 0))
    error_message = "cluster_vip_shared_ip must be a valid IPv4 address."
  }
}

variable "node_data" {
  description = <<-EOT
    Control plane and worker nodes, keyed by the node's IPv4 address. hostname, install_disk and install_image are
    required, cpu_cores, memory (MB), disk_size (GB) and proxmox_node are optional per node.
    The hostname is used as VM name, Talos hostname and Kubernetes node name, it must be a unique lowercase
    RFC 1123 DNS label. Without proxmox_node the VM is created on proxmox_target_node.
  EOT
  type = object({
    controlplanes = map(object({
      hostname      = string
      install_disk  = string
      install_image = string
      cpu_cores     = optional(number, 2)
      memory        = optional(number, 8192)
      disk_size     = optional(number, 50)
      proxmox_node  = optional(string)
    }))
    workers = optional(map(object({
      hostname      = string
      install_disk  = string
      install_image = string
      cpu_cores     = optional(number, 2)
      memory        = optional(number, 16384)
      disk_size     = optional(number, 50)
      proxmox_node  = optional(string)
    })), {})
  })

  validation {
    condition     = length(var.node_data.controlplanes) > 0
    error_message = "node_data.controlplanes must contain at least one control plane node."
  }

  validation {
    condition = alltrue([
      for ip in concat(keys(var.node_data.controlplanes), keys(var.node_data.workers)) : can(cidrhost("${ip}/32", 0))
    ])
    error_message = "All keys of node_data.controlplanes and node_data.workers must be valid IPv4 addresses."
  }

  validation {
    condition = alltrue([
      for node in concat(values(var.node_data.controlplanes), values(var.node_data.workers)) : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", node.hostname))
    ])
    error_message = "All hostnames must be lowercase RFC 1123 DNS labels of at most 63 characters, e.g. talos-cp-0."
  }

  validation {
    condition = length(distinct([
      for node in concat(values(var.node_data.controlplanes), values(var.node_data.workers)) : node.hostname
    ])) == length(var.node_data.controlplanes) + length(var.node_data.workers)
    error_message = "All hostnames must be unique."
  }
}

# Network
variable "network" {
  description = "Network for all nodes in CIDR notation, its prefix length is used for the node IP addresses"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.network))
    error_message = "network must be a valid IPv4 CIDR, e.g. 192.168.10.0/24."
  }
}

variable "network_gateway" {
  description = "Network gateway for all nodes"
  type        = string
}

variable "domain_name_servers" {
  description = "DNS servers for all nodes"
  type        = list(string)

  validation {
    condition     = length(var.domain_name_servers) > 0
    error_message = "At least one DNS server is required."
  }
}

variable "vlan_tag" {
  description = "VLAN tag for all nodes, default does not configure a VLAN"
  type        = number
  default     = 0
}

# Talos machine configuration
variable "allow_scheduling_on_control_planes" {
  description = "Allows scheduling of workloads on control plane nodes, e.g. for clusters without worker nodes"
  type        = bool
  default     = false
}

variable "talos_machine_config_patch_controlplane" {
  description = "Configuration patch which will be applied to all controlplane nodes"
  type        = string
  default     = ""
}

variable "talos_machine_config_patch_worker" {
  description = "Configuration patch which will be applied to all worker nodes"
  type        = string
  default     = ""
}

variable "extra_inline_manifests" {
  description = "Additional Kubernetes manifests which are applied by Talos on bootstrap, see https://www.talos.dev/latest/reference/configuration/v1alpha1/config/#Config.cluster.inlineManifests"
  type = list(object({
    name     = string
    contents = string
  }))
  default = []
}

# Gateway API
variable "gateway_api_crds_enabled" {
  description = "Installs the Gateway API v1.6.1 CRDs (standard channel) on bootstrap, required by Cilium's Gateway API support"
  type        = bool
  default     = true
}

# Cilium
variable "cilium_version" {
  description = "Version of the Cilium Helm chart"
  type        = string
  default     = "1.20.0"
}

variable "ingress_controller_enabled" {
  description = "Enables the Cilium Ingress controller, see https://docs.cilium.io/en/stable/network/servicemesh/ingress/"
  type        = bool
  default     = true
}

variable "cilium_helm_set" {
  description = "Additional Helm values for Cilium, applied after the module's defaults so they can override them"
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default = []
}

variable "cilium_helm_values" {
  description = "Additional Helm values for Cilium as YAML documents"
  type        = list(string)
  default     = []
}
