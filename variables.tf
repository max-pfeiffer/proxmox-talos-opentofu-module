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
  description = "Proxmox datastore the Talos Linux ISO image is downloaded to, it must support the `iso` content type. Ignored when `talos_linux_iso_file_id` is set."
  type        = string
  default     = "local"
}

variable "proxmox_iso_download_node" {
  description = "Proxmox node the Talos Linux ISO image is downloaded to once, for a `proxmox_iso_datastore` which is shared by all Proxmox nodes, e.g. NFS or CephFS. By default the image is downloaded to every Proxmox node which hosts a virtual machine. Ignored when `talos_linux_iso_file_id` is set."
  type        = string
  default     = null
}

variable "proxmox_network_bridge" {
  description = "Proxmox network bridge the virtual machines are attached to"
  type        = string
  default     = "vmbr0"
}

variable "proxmox_pool_id" {
  description = "Existing Proxmox resource pool the virtual machines are added to, e.g. for permissions or backup jobs selecting the pool. The pool must exist, the module does not manage it."
  type        = string
  default     = null
}

variable "proxmox_vm_tags" {
  description = "Additional Proxmox tags for all virtual machines. The module always tags them with `talos`, the `cluster_name` and the node role `controlplane` or `worker`."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for tag in var.proxmox_vm_tags : can(regex("^[a-z0-9_][a-z0-9_+.-]*$", tag))])
    error_message = "All proxmox_vm_tags must be lowercase Proxmox tags, starting with a letter, digit or underscore and containing only letters, digits and _ + . -"
  }
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

  validation {
    condition     = can(regex("^v?\\d+\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a semantic version, e.g. 1.36.3."
  }
}

variable "talos_linux_iso_image_url" {
  description = "URL of the Talos ISO image for initially booting the VM. It is downloaded as `talos-<cluster_name>-<URL hash>.iso`. Ignored when `talos_linux_iso_file_id` is set."
  type        = string
  default     = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.13.8/nocloud-amd64.iso"
}

variable "talos_linux_iso_file_id" {
  description = "ID of an existing Talos ISO image for initially booting the VM, e.g. `local:iso/talos-v1.13.8.iso`, which is managed outside of this module. It must be available on every Proxmox node which hosts a virtual machine. When set, the module does not download the image."
  type        = string
  default     = null

  validation {
    condition     = var.talos_linux_iso_file_id == null || can(regex("^[^:]+:iso/[^/]+$", var.talos_linux_iso_file_id))
    error_message = "talos_linux_iso_file_id must be an ISO file ID in the format <datastore>:iso/<file name>."
  }
}

variable "cluster_name" {
  description = "Name of the Talos cluster, also used as Proxmox tag of the virtual machines and in the ISO image file name. It must be a lowercase RFC 1123 DNS label."
  type        = string
  default     = "talos"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be a lowercase RFC 1123 DNS label of at most 63 characters, e.g. talos-prod."
  }
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
    Control plane and worker nodes, keyed by the node's IPv4 address. hostname, vm_id, install_disk and install_image
    are required, cpu_cores, memory (MB), disk_size (GB) and proxmox_node are optional per node.
    vm_id is the Proxmox VM ID, it must be unique in the Proxmox cluster and between 100 and 999999999. Changing it
    replaces the virtual machine.
    The hostname is used as VM name, Talos hostname and Kubernetes node name, it must be a unique lowercase
    RFC 1123 DNS label. Without proxmox_node the VM is created on proxmox_target_node.
    At most five control planes are supported, they are upgraded one at a time in numerical IP order.
  EOT
  type = object({
    controlplanes = map(object({
      hostname      = string
      vm_id         = number
      install_disk  = string
      install_image = string
      cpu_cores     = optional(number, 2)
      memory        = optional(number, 8192)
      disk_size     = optional(number, 50)
      proxmox_node  = optional(string)
    }))
    workers = optional(map(object({
      hostname      = string
      vm_id         = number
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

  # Every control plane position has its own talos_machine block, see talos_linux.tf
  validation {
    condition     = length(var.node_data.controlplanes) <= 5
    error_message = "node_data.controlplanes must contain at most five control plane nodes."
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

  # Proxmox VM IDs are integers from 100 to 999999999, lower IDs are reserved
  validation {
    condition = alltrue([
      for node in concat(values(var.node_data.controlplanes), values(var.node_data.workers)) : floor(node.vm_id) == node.vm_id && node.vm_id >= 100 && node.vm_id <= 999999999
    ])
    error_message = "All vm_ids must be integers between 100 and 999999999."
  }

  validation {
    condition = length(distinct([
      for node in concat(values(var.node_data.controlplanes), values(var.node_data.workers)) : node.vm_id
    ])) == length(var.node_data.controlplanes) + length(var.node_data.workers)
    error_message = "All vm_ids must be unique."
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
  description = "Installs the Gateway API CRDs (standard channel) of gateway_api_version on bootstrap, the control plane nodes download them from GitHub. When disabling it while gateway_api_enabled is true, install the CRDs required by Cilium yourself, see https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/"
  type        = bool
  default     = true
}

variable "gateway_api_version" {
  description = "Version of the Gateway API CRDs, e.g. v1.6.3. Defaults to the version supported by the Cilium minor version, see https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/"
  type        = string
  default     = null

  validation {
    condition     = var.gateway_api_version == null || can(regex("^v\\d+\\.\\d+\\.\\d+$", var.gateway_api_version))
    error_message = "gateway_api_version must be a Gateway API release tag, e.g. v1.6.3."
  }
}

variable "gateway_api_enabled" {
  description = "Enables Cilium's Gateway API support, see https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/"
  type        = bool
  default     = true
}

# Cilium
variable "cilium_version" {
  description = "Version of the Cilium Helm chart"
  type        = string
  default     = "1.20.4"

  validation {
    condition     = can(regex("^v?\\d+\\.\\d+\\.\\d+", var.cilium_version))
    error_message = "cilium_version must be a semantic version, e.g. 1.20.0."
  }
}

variable "cilium_kubernetes_compatibility_check" {
  description = "Fails the plan if the Cilium minor version is not e2e tested with the Kubernetes minor version, see https://docs.cilium.io/en/stable/network/kubernetes/compatibility/. Disable it to run an untested combination deliberately."
  type        = bool
  default     = true
}

variable "cilium_gateway_api_compatibility_check" {
  description = "Fails the plan if gateway_api_version is not the Gateway API minor version supported by the Cilium minor version, see https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/. Disable it to run an untested combination deliberately."
  type        = bool
  default     = true
}

variable "ingress_controller_enabled" {
  description = "Enables the Cilium Ingress controller, see https://docs.cilium.io/en/stable/network/servicemesh/ingress/. Disabled by default, the Gateway API supersedes it and its shared LoadBalancer Service takes an address of the LoadBalancer IP pool."
  type        = bool
  default     = false
}

variable "cilium_helm_set" {
  description = "Additional Helm values for Cilium, applied after the module's defaults and cilium_helm_values so they override both"
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default = []
}

variable "cilium_helm_values" {
  description = "Additional Helm values for Cilium as YAML documents, applied in order after the module's defaults so they can override them"
  type        = list(string)
  default     = []
}
