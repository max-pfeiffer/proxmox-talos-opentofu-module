resource "proxmox_virtual_environment_vm" "kubernetes_control_plane" {
  for_each        = var.node_data.controlplanes
  name            = each.value.hostname
  description     = "Kubernetes Control Plane"
  node_name       = local.controlplane_proxmox_nodes[each.key]
  started         = true
  stop_on_destroy = true
  boot_order      = ["virtio0", "ide2"]

  agent {
    enabled = true
  }

  operating_system {
    type = "l26"
  }

  cpu {
    cores = each.value.cpu_cores
    type  = var.vm_cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  vga {
    type = "std"
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_download_file.talos_linux_iso_image[local.controlplane_proxmox_nodes[each.key]].id
  }

  disk {
    interface    = "virtio0"
    datastore_id = var.proxmox_storage_device
    size         = each.value.disk_size
    discard      = "on"
  }

  network_device {
    model   = "virtio"
    bridge  = var.proxmox_network_bridge
    vlan_id = var.vlan_tag
  }

  # Cloud init setup
  initialization {
    interface    = "ide0"
    datastore_id = var.proxmox_storage_device

    ip_config {
      ipv4 {
        address = "${each.key}/${local.network_prefix_length}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.domain_name_servers
    }
  }
}

resource "proxmox_virtual_environment_vm" "kubernetes_worker" {
  for_each        = var.node_data.workers
  name            = each.value.hostname
  description     = "Kubernetes Worker Node"
  node_name       = local.worker_proxmox_nodes[each.key]
  started         = true
  stop_on_destroy = true
  boot_order      = ["virtio0", "ide2"]

  agent {
    enabled = true
  }

  operating_system {
    type = "l26"
  }

  cpu {
    cores = each.value.cpu_cores
    type  = var.vm_cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  vga {
    type = "std"
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_download_file.talos_linux_iso_image[local.worker_proxmox_nodes[each.key]].id
  }

  disk {
    interface    = "virtio0"
    datastore_id = var.proxmox_storage_device
    size         = each.value.disk_size
    discard      = "on"
  }

  network_device {
    model   = "virtio"
    bridge  = var.proxmox_network_bridge
    vlan_id = var.vlan_tag
  }

  # Cloud init setup
  initialization {
    interface    = "ide0"
    datastore_id = var.proxmox_storage_device

    ip_config {
      ipv4 {
        address = "${each.key}/${local.network_prefix_length}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.domain_name_servers
    }
  }
}
