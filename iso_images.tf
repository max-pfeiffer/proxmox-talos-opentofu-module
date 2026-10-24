locals {
  # The file name is unique per cluster and image URL: clusters sharing a Proxmox datastore never manage
  # the same file, and a new image is downloaded next to the old one instead of replacing it in place
  talos_linux_iso_image_filename = "talos-${var.cluster_name}-${substr(sha256(var.talos_linux_iso_image_url), 0, 12)}.iso"

  # Proxmox nodes the ISO image is downloaded to: none for an existing image, a single node for a shared
  # datastore, otherwise every Proxmox node which hosts a virtual machine
  iso_download_nodes = (
    var.talos_linux_iso_file_id != null ? toset([]) :
    var.proxmox_iso_download_node != null ? toset([var.proxmox_iso_download_node]) :
    local.proxmox_nodes
  )

  # ISO file ID per Proxmox node hosting a virtual machine
  iso_file_ids = {
    for node in local.proxmox_nodes : node => (
      var.talos_linux_iso_file_id != null ? var.talos_linux_iso_file_id :
      proxmox_download_file.talos_linux_iso_image[coalesce(var.proxmox_iso_download_node, node)].id
    )
  }
}

resource "proxmox_download_file" "talos_linux_iso_image" {
  for_each     = local.iso_download_nodes
  content_type = "iso"
  datastore_id = var.proxmox_iso_datastore
  node_name    = each.key
  url          = var.talos_linux_iso_image_url
  file_name    = local.talos_linux_iso_image_filename
  # Fail on a file which is not managed by this cluster instead of deleting it, other clusters may use it
  overwrite_unmanaged = false

  # The virtual machines are switched to the new image before the old one is deleted
  lifecycle {
    create_before_destroy = true
  }
}
