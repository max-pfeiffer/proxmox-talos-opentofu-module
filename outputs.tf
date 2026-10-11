output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubeconfig for cluster administration"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "kubernetes_client_configuration" {
  description = "Kubernetes API host and client credentials, e.g. for configuring the kubernetes and helm providers. Pass the module a separate helm provider then, see the Providers section of the README."
  value       = talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client configuration (CA certificate, client certificate and key)"
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}

output "machine_secrets" {
  description = "Talos machine secrets of the cluster, keep them safe for disaster recovery"
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}

output "cluster_name" {
  description = "Name of the Talos cluster"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint of the cluster"
  value       = local.cluster_endpoint
}

output "controlplane_ips" {
  description = "IP addresses of the control plane nodes"
  value       = keys(var.node_data.controlplanes)
}

output "worker_ips" {
  description = "IP addresses of the worker nodes"
  value       = keys(var.node_data.workers)
}

output "controlplane_vm_ids" {
  description = "Proxmox VM IDs of the control plane nodes, keyed by IP address"
  value       = { for ip, vm in proxmox_virtual_environment_vm.kubernetes_control_plane : ip => vm.vm_id }
}

output "worker_vm_ids" {
  description = "Proxmox VM IDs of the worker nodes, keyed by IP address"
  value       = { for ip, vm in proxmox_virtual_environment_vm.kubernetes_worker : ip => vm.vm_id }
}
