# Basic example
A minimal Kubernetes cluster with one control plane and one worker node on a single Proxmox VE node.

## Prerequisites
* [OpenTofu](https://opentofu.org/) >= 1.11.0
* A Proxmox VE API token with permissions to manage virtual machines, storage and downloads
* Free IP addresses in your network for both nodes and the shared virtual IP of the Kubernetes API

## Usage
Adjust the Proxmox node, datastore, network and node IP addresses in `main.tf` to your environment, then provide the
Proxmox API credentials:
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
Remove the cluster with `tofu destroy`.
