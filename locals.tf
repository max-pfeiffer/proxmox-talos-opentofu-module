locals {
  cluster_endpoint = "https://${var.cluster_vip_shared_ip}:6443"

  # Prefix length of the node network, used for the node IP addresses
  network_prefix_length = split("/", var.network)[1]

  # Proxmox node per Talos node, falling back to proxmox_target_node
  controlplane_proxmox_nodes = { for ip, node in var.node_data.controlplanes : ip => coalesce(node.proxmox_node, var.proxmox_target_node) }
  worker_proxmox_nodes       = { for ip, node in var.node_data.workers : ip => coalesce(node.proxmox_node, var.proxmox_target_node) }

  # Proxmox nodes which host a virtual machine
  proxmox_nodes = toset(concat(values(local.controlplane_proxmox_nodes), values(local.worker_proxmox_nodes)))

  # Control plane IPs sorted numerically instead of lexically, e.g. 192.168.10.9 before 192.168.10.10
  controlplane_ips_sorted = [
    for padded in sort([for ip in keys(var.node_data.controlplanes) : format("%03d.%03d.%03d.%03d", split(".", ip)...)]) :
    join(".", [for octet in split(".", padded) : tostring(tonumber(octet))])
  ]

  # Position of every control plane in controlplane_ips_sorted, selects its talos_machine block
  controlplane_positions = { for i, ip in local.controlplane_ips_sorted : ip => i }

  # Talos API endpoint for bootstrapping, Kubernetes upgrades and retrieving the kubeconfig
  bootstrap_node = local.controlplane_ips_sorted[0]

  # Gateway API CRDs (standard channel), the version supported by the Cilium minor version unless set explicitly.
  # null for an unknown Cilium minor version, a precondition of the Cilium Helm template reports it.
  cilium_gateway_api_version       = lookup(local.cilium_gateway_api_versions, local.cilium_minor_version, null)
  gateway_api_version              = var.gateway_api_version != null ? var.gateway_api_version : local.cilium_gateway_api_version
  gateway_api_minor_version        = local.gateway_api_version != null ? regex("^v\\d+\\.\\d+", local.gateway_api_version) : null
  cilium_gateway_api_minor_version = local.cilium_gateway_api_version != null ? regex("^v\\d+\\.\\d+", local.cilium_gateway_api_version) : null

  # Manifests downloaded by the control plane nodes on bootstrap. Talos applies them together with the inline
  # manifests and applies CRDs first, so the Gateway API CRDs exist when Cilium starts.
  extra_manifests = var.gateway_api_crds_enabled && local.gateway_api_version != null ? [
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${local.gateway_api_version}/standard-install.yaml",
  ] : []

  # Manifests applied by Talos on bootstrap, the order is preserved
  inline_manifests = concat(
    [
      {
        name     = "cilium"
        contents = data.helm_template.cilium.manifest
      },
    ],
    var.extra_inline_manifests,
  )
}
