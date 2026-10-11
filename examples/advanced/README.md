# Advanced example
A highly available Kubernetes cluster spread across a three node Proxmox VE cluster:
* three control plane and three worker nodes, each placed on a Proxmox node with `proxmox_node`
* per node CPU, memory and disk sizing
* nodes in VLAN 10
* Talos machine configuration patch for registry mirrors on a Harbor pull-through cache
* additional Cilium Helm values enabling Hubble Relay and UI, Cilium's Ingress controller disabled
* the installed Talos version and Image Factory schematic defined once and shared by the ISO and installer images
* a separate `helm` provider for rendering Cilium, so a default `helm` provider can deploy into the new cluster

## Prerequisites
* [OpenTofu](https://opentofu.org/) >= 1.11.0
* A Proxmox VE cluster and an API token with permissions to manage virtual machines, storage and downloads
* Free IP addresses in VLAN 10 for all six nodes and the shared virtual IP of the Kubernetes API
* A registry mirror, or remove `registry_mirrors_patch` from `main.tf`

## Usage
Adjust the Proxmox nodes, datastores, network, node IP addresses and the registry mirror in `main.tf` to your
environment, then provide the Proxmox API credentials:
```shell
cp terraform.tfvars.example terraform.tfvars
```
Create the cluster and grab the kube config file:
```shell
tofu init
tofu apply
tofu output -raw kubeconfig > ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes
```
Upgrade Talos Linux by bumping `talos_installed_version` in `main.tf` and applying with `tofu apply -parallelism=1`,
see [Upgrading Talos](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster#upgrading-talos).

Remove the cluster with `tofu destroy`.
