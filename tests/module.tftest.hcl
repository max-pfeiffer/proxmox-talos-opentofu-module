# Plan-only tests with mocked providers, they run offline without Proxmox or a Talos cluster.

mock_provider "proxmox" {
  # The VM's cdrom validates the file ID format, generated mock values would fail
  mock_resource "proxmox_download_file" {
    defaults = {
      id = "local:iso/talos.iso"
    }
  }
}

mock_provider "talos" {}
mock_provider "helm" {}

variables {
  proxmox_target_node    = "pve-0"
  proxmox_storage_device = "local-lvm"
  talos_version          = "1.13.8"
  kubernetes_version     = "1.36.3"
  cluster_name           = "test"
  cluster_vip_shared_ip  = "192.168.10.100"
  network                = "192.168.10.0/24"
  network_gateway        = "192.168.10.1"
  domain_name_servers    = ["192.168.10.1"]
  node_data = {
    controlplanes = {
      "192.168.10.101" = {
        install_disk  = "/dev/vda"
        install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
        hostname      = "test-cp-0"
      }
      "192.168.10.102" = {
        install_disk  = "/dev/vda"
        install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
        hostname      = "test-cp-1"
        proxmox_node  = "pve-1"
      }
    }
    workers = {
      "192.168.10.103" = {
        install_disk  = "/dev/vda"
        install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
        hostname      = "test-worker-0"
        proxmox_node  = "pve-1"
      }
    }
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = toset(keys(proxmox_download_file.talos_linux_iso_image)) == toset(["pve-0", "pve-1"])
    error_message = "The ISO image must be downloaded exactly once to every Proxmox node hosting a VM."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_control_plane["192.168.10.102"].node_name == "pve-1"
    error_message = "proxmox_node must override proxmox_target_node."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_control_plane["192.168.10.101"].node_name == "pve-0"
    error_message = "Nodes without proxmox_node must be created on proxmox_target_node."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_worker["192.168.10.103"].memory[0].dedicated == 16384
    error_message = "Workers must default to 16384 MB memory."
  }

  assert {
    condition     = local.cluster_endpoint == "https://192.168.10.100:6443"
    error_message = "The cluster endpoint must be the shared VIP."
  }

  assert {
    condition     = [for m in local.inline_manifests : m.name] == ["gateway-api", "cilium"]
    error_message = "Gateway API CRDs must be applied before Cilium."
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches) == 2
    error_message = "A node must get the base and the hostname patch."
  }
}

run "optional_features" {
  command = plan

  variables {
    gateway_api_crds_enabled                = false
    talos_machine_config_patch_controlplane = "machine: {}"
    extra_inline_manifests = [
      {
        name     = "extra"
        contents = "apiVersion: v1"
      },
    ]
  }

  assert {
    condition     = [for m in local.inline_manifests : m.name] == ["cilium", "extra"]
    error_message = "Disabled Gateway API CRDs must be omitted and extra manifests appended."
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane["192.168.10.102"].config_patches) == 3
    error_message = "The control plane patch must be appended."
  }

  assert {
    condition     = length(data.talos_machine_configuration.worker["192.168.10.103"].config_patches) == 2
    error_message = "An empty worker patch must not be appended."
  }
}

run "rejects_invalid_node_ip" {
  command = plan

  variables {
    node_data = {
      controlplanes = {
        "not-an-ip" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-0"
        }
      }
    }
  }

  expect_failures = [var.node_data]
}

run "rejects_missing_control_plane" {
  command = plan

  variables {
    node_data = {
      controlplanes = {}
    }
  }

  expect_failures = [var.node_data]
}

run "rejects_invalid_network" {
  command = plan

  variables {
    network = "192.168.10.0"
  }

  expect_failures = [var.network]
}

run "rejects_invalid_vip" {
  command = plan

  variables {
    cluster_vip_shared_ip = "192.168.10"
  }

  expect_failures = [var.cluster_vip_shared_ip]
}

run "hostname_used_as_node_name" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_control_plane["192.168.10.101"].name == "test-cp-0"
    error_message = "The hostname must be used as control plane VM name."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_worker["192.168.10.103"].name == "test-worker-0"
    error_message = "The hostname must be used as worker VM name."
  }

  assert {
    condition     = strcontains(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches[1], "hostname: test-cp-0\n")
    error_message = "The hostname must be set as control plane Talos hostname."
  }

  assert {
    condition     = strcontains(data.talos_machine_configuration.worker["192.168.10.103"].config_patches[1], "hostname: test-worker-0\n")
    error_message = "The hostname must be set as worker Talos hostname."
  }
}

run "rejects_invalid_hostname" {
  command = plan

  variables {
    node_data = {
      controlplanes = {
        "192.168.10.101" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "Test_CP_0"
        }
      }
    }
  }

  expect_failures = [var.node_data]
}

run "rejects_duplicate_hostnames" {
  command = plan

  variables {
    node_data = {
      controlplanes = {
        "192.168.10.101" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-node"
        }
      }
      workers = {
        "192.168.10.103" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-node"
        }
      }
    }
  }

  expect_failures = [var.node_data]
}

run "rejects_talos_version_without_hostname_config" {
  command = plan

  variables {
    talos_version = "v1.11.5"
  }

  expect_failures = [var.talos_version]
}

run "default_route_via_gateway" {
  command = plan

  assert {
    condition     = strcontains(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches[0], "- network: 0.0.0.0/0\n            gateway: 192.168.10.1")
    error_message = "Control plane nodes must get a default route via the gateway."
  }

  assert {
    condition     = strcontains(data.talos_machine_configuration.worker["192.168.10.103"].config_patches[0], "- network: 0.0.0.0/0\n            gateway: 192.168.10.1")
    error_message = "Worker nodes must get a default route via the gateway."
  }
}

run "bootstrap_node_sorted_numerically" {
  command = plan

  variables {
    node_data = {
      controlplanes = {
        "192.168.10.10" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-10"
        }
        "192.168.10.9" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-9"
        }
        "192.168.10.100" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-100"
        }
      }
    }
  }

  assert {
    condition     = talos_cluster.this.node == "192.168.10.9" && talos_cluster_kubeconfig.this.node == "192.168.10.9"
    error_message = "The bootstrap node must be the numerically lowest control plane IP."
  }
}
