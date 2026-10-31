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
        vm_id         = 10101
      }
      "192.168.10.102" = {
        install_disk  = "/dev/vda"
        install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
        hostname      = "test-cp-1"
        vm_id         = 10102
        proxmox_node  = "pve-1"
      }
    }
    workers = {
      "192.168.10.103" = {
        install_disk  = "/dev/vda"
        install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
        hostname      = "test-worker-0"
        vm_id         = 10103
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
    condition     = proxmox_download_file.talos_linux_iso_image["pve-0"].file_name == "talos-test-${substr(sha256(var.talos_linux_iso_image_url), 0, 12)}.iso"
    error_message = "The ISO file name must be unique per cluster and image URL."
  }

  assert {
    condition     = !proxmox_download_file.talos_linux_iso_image["pve-0"].overwrite_unmanaged
    error_message = "An ISO file not managed by the cluster must never be overwritten."
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
    condition     = [for m in local.inline_manifests : m.name] == ["cilium"]
    error_message = "Cilium must be the only inline manifest by default."
  }

  assert {
    condition     = strcontains(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches[0], "extraManifests:\n    - https://github.com/kubernetes-sigs/gateway-api/releases/download/${local.gateway_api_version}/standard-install.yaml\n")
    error_message = "Control planes must download the Gateway API CRDs of the pinned version."
  }

  assert {
    condition     = !strcontains(data.talos_machine_configuration.worker["192.168.10.103"].config_patches[0], "extraManifests")
    error_message = "Workers must not download extra manifests."
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches) == 2
    error_message = "A node must get the base and the hostname patch."
  }

  assert {
    condition     = !contains(keys(local.cilium_values), "ingressController")
    error_message = "The Cilium Ingress controller must be disabled by default."
  }

  assert {
    condition     = data.helm_template.cilium.values[0] == yamlencode(local.cilium_values)
    error_message = "The module's Cilium defaults must be the first values document, so cilium_helm_values can override them."
  }

  assert {
    condition = alltrue([
      local.cilium_values.rollOutCiliumPods,
      local.cilium_values.operator.rollOutPods,
      local.cilium_values.envoy.rollOutPods,
    ])
    error_message = "Cilium pods must be rolled out when their configuration changes."
  }

  assert {
    condition     = local.cilium_values.operator.replicas == 2
    error_message = "Clusters with several nodes must run two Cilium operator replicas."
  }

  assert {
    condition     = local.cilium_values.gatewayAPI.enabled
    error_message = "Cilium's Gateway API support must be enabled by default."
  }

  assert {
    condition     = local.gateway_api_version == local.cilium_gateway_api_versions[local.cilium_minor_version]
    error_message = "The Gateway API version must default to the version supported by the Cilium minor version."
  }
}

run "existing_iso_image" {
  command = plan

  variables {
    talos_linux_iso_file_id = "nfs:iso/talos-v1.13.8.iso"
  }

  assert {
    condition     = length(proxmox_download_file.talos_linux_iso_image) == 0
    error_message = "No ISO image must be downloaded when an existing one is passed in."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_control_plane["192.168.10.102"].cdrom[0].file_id == "nfs:iso/talos-v1.13.8.iso"
    error_message = "Control planes must boot the existing ISO image."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_worker["192.168.10.103"].cdrom[0].file_id == "nfs:iso/talos-v1.13.8.iso"
    error_message = "Workers must boot the existing ISO image."
  }
}

run "shared_iso_datastore" {
  command = plan

  variables {
    proxmox_iso_datastore     = "nfs"
    proxmox_iso_download_node = "pve-0"
  }

  assert {
    condition     = toset(keys(proxmox_download_file.talos_linux_iso_image)) == toset(["pve-0"])
    error_message = "The ISO image must be downloaded once to a shared datastore."
  }
}

run "rejects_invalid_iso_file_id" {
  command = plan

  variables {
    talos_linux_iso_file_id = "talos.iso"
  }

  expect_failures = [var.talos_linux_iso_file_id]
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
    error_message = "Extra inline manifests must be appended."
  }

  assert {
    condition     = !strcontains(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches[0], "extraManifests")
    error_message = "Disabled Gateway API CRDs must not be downloaded."
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

run "ingress_controller" {
  command = plan

  variables {
    ingress_controller_enabled = true
  }

  assert {
    condition     = local.cilium_values.ingressController == { enabled = true, loadbalancerMode = "dedicated" }
    error_message = "The enabled Cilium Ingress controller must be configured."
  }
}

run "single_node_cluster" {
  command = plan

  variables {
    allow_scheduling_on_control_planes = true
    node_data = {
      controlplanes = {
        "192.168.10.101" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-0"
          vm_id         = 10101
        }
      }
    }
  }

  assert {
    condition     = local.cilium_values.operator.replicas == 1
    error_message = "A single node cluster must run one Cilium operator replica."
  }
}

run "gateway_api_disabled" {
  command = plan

  variables {
    gateway_api_enabled = false
  }

  assert {
    condition     = !local.cilium_values.gatewayAPI.enabled
    error_message = "Cilium's Gateway API support must be disableable."
  }
}

run "cilium_helm_values_override_defaults" {
  command = plan

  variables {
    cilium_helm_values = ["bpf:\n  masquerade: false\n"]
    cilium_helm_set = [
      {
        name  = "hubble.relay.enabled"
        value = "true"
      },
    ]
  }

  assert {
    condition     = tolist(data.helm_template.cilium.values) == tolist([yamlencode(local.cilium_values), "bpf:\n  masquerade: false\n"])
    error_message = "cilium_helm_values must be applied after the module's defaults."
  }

  assert {
    condition     = [for s in data.helm_template.cilium.set : s.name] == ["hubble.relay.enabled"]
    error_message = "cilium_helm_set must only contain the user's values."
  }
}

run "rejects_untested_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "1.40.0"
  }

  expect_failures = [data.helm_template.cilium]
}

run "rejects_unknown_cilium_minor_version" {
  command = plan

  variables {
    cilium_version = "1.99.0"
  }

  expect_failures = [data.helm_template.cilium]
}

run "gateway_api_version_follows_cilium" {
  command = plan

  variables {
    cilium_version     = "1.19.4"
    kubernetes_version = "1.35.2"
  }

  assert {
    condition     = local.gateway_api_version == "v1.4.1"
    error_message = "Cilium 1.19 must get the Gateway API v1.4 CRDs."
  }

  assert {
    condition     = strcontains(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches[0], "/gateway-api/releases/download/v1.4.1/standard-install.yaml")
    error_message = "Control planes must download the Gateway API CRDs supported by Cilium."
  }
}

run "gateway_api_newer_patch_version" {
  command = plan

  variables {
    gateway_api_version = "v1.6.9"
  }

  assert {
    condition     = strcontains(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches[0], "/gateway-api/releases/download/v1.6.9/standard-install.yaml")
    error_message = "An explicit gateway_api_version must be downloaded."
  }
}

run "rejects_gateway_api_minor_version_unsupported_by_cilium" {
  command = plan

  variables {
    gateway_api_version = "v1.7.0"
  }

  expect_failures = [data.helm_template.cilium]
}

run "gateway_api_older_patch_version" {
  command = plan

  variables {
    gateway_api_version = "v1.6.1"
  }

  assert {
    condition     = strcontains(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches[0], "/gateway-api/releases/download/v1.6.1/standard-install.yaml")
    error_message = "Older Gateway API patch versions must be accepted, they don't change the CRD schemas."
  }
}

run "rejects_gateway_api_crds_for_older_cilium" {
  command = plan

  variables {
    cilium_version      = "1.19.4"
    kubernetes_version  = "1.35.2"
    gateway_api_version = "v1.6.1"
  }

  expect_failures = [data.helm_template.cilium]
}

run "skips_gateway_api_compatibility_check" {
  command = plan

  variables {
    gateway_api_version                    = "v1.7.0"
    cilium_gateway_api_compatibility_check = false
  }

  assert {
    condition     = strcontains(data.talos_machine_configuration.controlplane["192.168.10.101"].config_patches[0], "/gateway-api/releases/download/v1.7.0/standard-install.yaml")
    error_message = "The check must be skippable."
  }
}

run "gateway_api_crds_managed_externally" {
  command = plan

  variables {
    gateway_api_crds_enabled = false
    gateway_api_version      = "v1.7.0"
  }

  assert {
    condition     = length(local.extra_manifests) == 0
    error_message = "Externally managed Gateway API CRDs must neither be downloaded nor checked."
  }
}

run "rejects_unknown_cilium_minor_version_without_gateway_api_version" {
  command = plan

  variables {
    cilium_version                        = "1.99.0"
    cilium_kubernetes_compatibility_check = false
  }

  expect_failures = [data.helm_template.cilium]
}

run "unknown_cilium_minor_version_with_gateway_api_version" {
  command = plan

  variables {
    cilium_version                         = "1.99.0"
    cilium_kubernetes_compatibility_check  = false
    cilium_gateway_api_compatibility_check = false
    gateway_api_version                    = "v1.9.0"
  }

  assert {
    condition     = local.gateway_api_version == "v1.9.0"
    error_message = "An explicit gateway_api_version must be used for an unknown Cilium minor version."
  }
}

run "rejects_invalid_gateway_api_version" {
  command = plan

  variables {
    gateway_api_version = "1.6.1"
  }

  expect_failures = [var.gateway_api_version]
}

run "skips_kubernetes_compatibility_check" {
  command = plan

  variables {
    kubernetes_version                    = "1.40.0"
    cilium_kubernetes_compatibility_check = false
  }

  assert {
    condition     = local.kubernetes_minor_version == "1.40"
    error_message = "The Kubernetes minor version must be derived from kubernetes_version."
  }
}

run "rejects_invalid_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "latest"
  }

  expect_failures = [var.kubernetes_version]
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
          vm_id         = 10101
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
          vm_id         = 10101
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
          vm_id         = 10101
        }
      }
      workers = {
        "192.168.10.103" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-node"
          vm_id         = 10103
        }
      }
    }
  }

  expect_failures = [var.node_data]
}

run "vm_ids_tags_and_pool" {
  command = plan

  variables {
    proxmox_pool_id = "kubernetes"
    proxmox_vm_tags = ["prod", "talos"]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_control_plane["192.168.10.101"].vm_id == 10101
    error_message = "The vm_id must be used as control plane VM ID."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_worker["192.168.10.103"].vm_id == 10103
    error_message = "The vm_id must be used as worker VM ID."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_control_plane["192.168.10.101"].tags == tolist(["controlplane", "prod", "talos", "test"])
    error_message = "Control planes must be tagged with talos, the cluster name, their role and proxmox_vm_tags, sorted and deduplicated."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.kubernetes_worker["192.168.10.103"].tags == tolist(["prod", "talos", "test", "worker"])
    error_message = "Workers must be tagged with talos, the cluster name, their role and proxmox_vm_tags, sorted and deduplicated."
  }

  assert {
    condition = alltrue([
      proxmox_virtual_environment_vm.kubernetes_control_plane["192.168.10.101"].pool_id == "kubernetes",
      proxmox_virtual_environment_vm.kubernetes_worker["192.168.10.103"].pool_id == "kubernetes",
    ])
    error_message = "All VMs must be added to proxmox_pool_id."
  }
}

run "rejects_duplicate_vm_ids" {
  command = plan

  variables {
    node_data = {
      controlplanes = {
        "192.168.10.101" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-0"
          vm_id         = 10101
        }
      }
      workers = {
        "192.168.10.103" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-worker-0"
          vm_id         = 10101
        }
      }
    }
  }

  expect_failures = [var.node_data]
}

run "rejects_reserved_vm_id" {
  command = plan

  variables {
    node_data = {
      controlplanes = {
        "192.168.10.101" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-0"
          vm_id         = 99
        }
      }
    }
  }

  expect_failures = [var.node_data]
}

run "rejects_fractional_vm_id" {
  command = plan

  variables {
    node_data = {
      controlplanes = {
        "192.168.10.101" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-0"
          vm_id         = 101.5
        }
      }
    }
  }

  expect_failures = [var.node_data]
}

run "rejects_invalid_vm_tag" {
  command = plan

  variables {
    proxmox_vm_tags = ["Prod Cluster"]
  }

  expect_failures = [var.proxmox_vm_tags]
}

run "rejects_invalid_cluster_name" {
  command = plan

  variables {
    cluster_name = "Test_Cluster"
  }

  expect_failures = [var.cluster_name]
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
          vm_id         = 10010
        }
        "192.168.10.9" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-9"
          vm_id         = 10009
        }
        "192.168.10.100" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-100"
          vm_id         = 10100
        }
      }
    }
  }

  assert {
    condition     = talos_cluster.this.node == "192.168.10.9" && talos_cluster_kubeconfig.this.node == "192.168.10.9"
    error_message = "The bootstrap node must be the numerically lowest control plane IP."
  }
}

run "controlplanes_chained_in_ip_order" {
  command = plan

  variables {
    node_data = {
      controlplanes = {
        "192.168.10.10" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-10"
          vm_id         = 10010
        }
        "192.168.10.9" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-9"
          vm_id         = 10009
        }
        "192.168.10.100" = {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-100"
          vm_id         = 10100
        }
      }
    }
  }

  assert {
    condition = [
      keys(talos_machine.controlplane_0),
      keys(talos_machine.controlplane_1),
      keys(talos_machine.controlplane_2),
      keys(talos_machine.controlplane_3),
      keys(talos_machine.controlplane_4),
    ] == [["192.168.10.9"], ["192.168.10.10"], ["192.168.10.100"], [], []]
    error_message = "Every control plane must be managed by the talos_machine block of its numerical IP position."
  }
}

run "rejects_more_than_five_control_planes" {
  command = plan

  variables {
    node_data = {
      controlplanes = {
        for i in range(6) : "192.168.10.${101 + i}" => {
          install_disk  = "/dev/vda"
          install_image = "factory.talos.dev/nocloud-installer/schematic:v1.13.8"
          hostname      = "test-cp-${i}"
          vm_id         = 10101 + i
        }
      }
    }
  }

  expect_failures = [var.node_data]
}
