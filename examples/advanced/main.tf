locals {
  # Talos Image Factory schematic with the QEMU guest agent extension, see https://factory.talos.dev/
  talos_schematic_id      = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
  talos_installed_version = "v1.13.8"
  install_image           = "factory.talos.dev/nocloud-installer/${local.talos_schematic_id}:${local.talos_installed_version}"

  registry_mirrors_patch = <<-EOT
    machine:
      registries:
        mirrors:
          docker.io:
            endpoints:
              - https://harbor.local/v2/docker-hub-cache
            overridePath: true
          ghcr.io:
            endpoints:
              - https://harbor.local/v2/github-cache
            overridePath: true
        config:
          harbor.local:
            tls:
              ca: BASE64_ENCODED_ROOT_CA_CERTIFICATE
  EOT
}

module "talos_cluster" {
  # Outside of this repository use the registry instead:
  # source  = "max-pfeiffer/talos-cluster/proxmox"
  # version = "<version>"
  source = "../.."

  providers = {
    helm = helm.render
  }

  # Proxmox
  proxmox_target_node    = "pve-0"
  proxmox_storage_device = "samsung-ssd"
  proxmox_iso_datastore  = "local"
  proxmox_network_bridge = "vmbr0"

  # Talos Linux
  # talos_version is the machine configuration contract, pin it to the version the cluster was created with.
  # The installed Talos version is driven by install_image.
  talos_version                  = "1.13.8"
  kubernetes_version             = "1.36.3"
  talos_linux_iso_image_url      = "https://factory.talos.dev/image/${local.talos_schematic_id}/${local.talos_installed_version}/nocloud-amd64.iso"
  talos_linux_iso_image_filename = "talos-linux-${local.talos_installed_version}-qemu-guest-agent-amd64.iso"

  cluster_name          = "your-cluster-name"
  cluster_vip_shared_ip = "192.168.10.100"

  # Network configuration, which is applied to all nodes
  network             = "192.168.10.0/24"
  network_gateway     = "192.168.10.1"
  domain_name_servers = ["192.168.10.1", "1.1.1.1"]
  vlan_tag            = 10

  # Nodes are spread across the Proxmox cluster with proxmox_node, defaults for resources are:
  # control planes 2 cores, 8192 MB, 50 GB / workers 2 cores, 16384 MB, 50 GB
  node_data = {
    controlplanes = {
      "192.168.10.101" = {
        install_disk  = "/dev/vda"
        install_image = local.install_image
        hostname      = "your-cluster-name-cp-0"
        proxmox_node  = "pve-0"
        cpu_cores     = 4
        memory        = 8192
        disk_size     = 50
      },
      "192.168.10.102" = {
        install_disk  = "/dev/vda"
        install_image = local.install_image
        hostname      = "your-cluster-name-cp-1"
        proxmox_node  = "pve-1"
      },
      "192.168.10.103" = {
        install_disk  = "/dev/vda"
        install_image = local.install_image
        hostname      = "your-cluster-name-cp-2"
        proxmox_node  = "pve-2"
      },
    }
    workers = {
      "192.168.10.104" = {
        install_disk  = "/dev/vda"
        install_image = local.install_image
        hostname      = "your-cluster-name-worker-0"
        proxmox_node  = "pve-0"
      },
      "192.168.10.105" = {
        install_disk  = "/dev/vda"
        install_image = local.install_image
        hostname      = "your-cluster-name-worker-1"
        proxmox_node  = "pve-1"
      },
      "192.168.10.106" = {
        install_disk  = "/dev/vda"
        install_image = local.install_image
        hostname      = "your-cluster-name-worker-2"
        proxmox_node  = "pve-2"
        memory        = 32768
        disk_size     = 100
      },
    }
  }

  # Config patches
  talos_machine_config_patch_controlplane = local.registry_mirrors_patch
  talos_machine_config_patch_worker       = local.registry_mirrors_patch

  # Cilium
  ingress_controller_enabled = false
  cilium_helm_set = [
    {
      name  = "hubble.relay.enabled"
      value = "true"
    },
    {
      name  = "hubble.ui.enabled"
      value = "true"
    },
  ]
}
