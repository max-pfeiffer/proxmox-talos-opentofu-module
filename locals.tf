locals {
  cluster_endpoint = "https://${var.cluster_vip_shared_ip}:6443"

  # Prefix length of the node network, used for the node IP addresses
  network_prefix_length = split("/", var.network)[1]

  # Proxmox node per Talos node, falling back to proxmox_target_node
  controlplane_proxmox_nodes = { for ip, node in var.node_data.controlplanes : ip => coalesce(node.proxmox_node, var.proxmox_target_node) }
  worker_proxmox_nodes       = { for ip, node in var.node_data.workers : ip => coalesce(node.proxmox_node, var.proxmox_target_node) }

  # The Talos ISO image is downloaded to every Proxmox node which hosts a virtual machine
  proxmox_nodes = toset(concat(values(local.controlplane_proxmox_nodes), values(local.worker_proxmox_nodes)))

  # Control plane IPs sorted numerically instead of lexically, e.g. 192.168.10.9 before 192.168.10.10
  controlplane_ips_sorted = [
    for padded in sort([for ip in keys(var.node_data.controlplanes) : format("%03d.%03d.%03d.%03d", split(".", ip)...)]) :
    join(".", [for octet in split(".", padded) : tostring(tonumber(octet))])
  ]

  # Talos API endpoint for bootstrapping, Kubernetes upgrades and retrieving the kubeconfig
  bootstrap_node = local.controlplane_ips_sorted[0]

  # Manifests applied by Talos on bootstrap, the order is preserved
  inline_manifests = concat(
    var.gateway_api_crds_enabled ? [
      {
        name     = "gateway-api"
        contents = file("${path.module}/gateway-api/gateway-api-crds-v1.6.1.yaml")
      },
    ] : [],
    [
      {
        name     = "cilium"
        contents = data.helm_template.cilium.manifest
      },
    ],
    var.extra_inline_manifests,
  )
}
