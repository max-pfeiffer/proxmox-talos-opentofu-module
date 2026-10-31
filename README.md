[![OpenTofu](https://img.shields.io/badge/OpenTofu-FFDA18?logo=opentofu&logoColor=black)](https://opentofu.org/)
[![Code quality](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/actions/workflows/code-quality.yaml/badge.svg)](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/actions/workflows/code-quality.yaml)
[![Release](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/actions/workflows/release.yaml/badge.svg)](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/actions/workflows/release.yaml)

# Proxmox Talos OpenTofu Module
An [OpenTofu](https://opentofu.org/) module which provisions a turnkey Kubernetes cluster with
[Talos Linux](https://www.talos.dev/) on a
[Proxmox VE hypervisor](https://www.proxmox.com/en/products/proxmox-virtual-environment/overview).

Kubernetes cluster features:
* [Talos Linux v1.13.8](https://www.talos.dev/)
* Kubernetes v1.36.3
* no kube-proxy
* [Cilium v1.20.0](https://cilium.io/) as Container Network Interface (CNI)
  * without kube-proxy
  * with [L2 loadbalancer support](https://docs.cilium.io/en/stable/network/l2-announcements/)
  * with [Ingress controller support](https://docs.cilium.io/en/stable/network/servicemesh/ingress/) (optional, disabled by default)
  * with [Gateway API support](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
  * with [Egress gateway support](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/)
* [Gateway API v1.6.1](https://gateway-api.sigs.k8s.io/) CRDs (standard channel) are installed (optional)
* control plane nodes share a [virtual IP](https://www.talos.dev/v1.13/talos-guides/network/vip/) as Kubernetes API endpoint
* Talos OS and Kubernetes upgrades are handled declaratively, see [Upgrading](#upgrading)

The module creates one virtual machine per node, downloads the Talos Linux ISO image to every Proxmox node which hosts
a virtual machine, applies the Talos machine configuration, bootstraps the cluster and returns `kubeconfig` and
`talosconfig`.

### Talos Linux ISO image
By default the module downloads the ISO image from `talos_linux_iso_image_url` to `proxmox_iso_datastore` on every
Proxmox node which hosts a virtual machine. The file is named `talos-<cluster_name>-<URL hash>.iso`, so several
clusters on the same Proxmox VE host each manage their own file and never delete or overwrite the image of another
cluster. A file with the same name which is not managed by the cluster fails the apply instead of being replaced,
so give every cluster on a Proxmox VE host a unique `cluster_name`.

* For a datastore shared by all Proxmox nodes, e.g. NFS or CephFS, set `proxmox_iso_download_node` to download the
  image only once.
* To share one image between clusters, manage it outside of this module, e.g. with a `proxmox_download_file`
  resource in a separate root module, and pass its ID with `talos_linux_iso_file_id`. The module then downloads
  nothing, and destroying a cluster leaves the image in place.

## Requirements
* [OpenTofu](https://opentofu.org/) >= 1.11.0
* A Proxmox VE API token with permissions to manage virtual machines, storage and downloads
* A Talos Linux image with the [QEMU guest agent extension](https://github.com/siderolabs/extensions/tree/main/guest-agents/qemu-guest-agent),
  build one with the [Talos Linux Image Factory](https://factory.talos.dev/) (platform `nocloud`)

## Usage
The module does not configure any providers. Configure the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
provider in your root module, the `siderolabs/talos` and `hashicorp/helm` providers need no configuration:
```hcl
provider "proxmox" {
  endpoint  = "https://192.168.1.25:8006/"
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true
}

module "talos_cluster" {
  source  = "max-pfeiffer/talos-cluster/proxmox"
  version = "0.1.0" # x-release-please-version

  proxmox_target_node    = "your-proxmox-node"
  proxmox_storage_device = "local-lvm"

  talos_version      = "1.13.8"
  kubernetes_version = "1.36.3"

  cluster_name          = "your-cluster-name"
  cluster_vip_shared_ip = "192.168.10.100"

  network             = "192.168.10.0/24"
  network_gateway     = "192.168.10.1"
  domain_name_servers = ["192.168.10.1"]

  node_data = {
    controlplanes = {
      "192.168.10.101" = {
        install_disk  = "/dev/vda"
        install_image = "factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.13.8"
        hostname      = "your-cluster-name-cp-0"
      }
    }
    workers = {
      "192.168.10.102" = {
        install_disk  = "/dev/vda"
        install_image = "factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.13.8"
        hostname      = "your-cluster-name-worker-0"
      }
    }
  }
}

output "kubeconfig" {
  value     = module.talos_cluster.kubeconfig
  sensitive = true
}
```
The module is also available directly from GitHub, e.g. for unreleased changes:
`source = "git::https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster.git?ref=v0.1.0"`. <!-- x-release-please-version -->

### Providers
The module declares its providers in `required_providers` but configures none of them, so it can be used with
`count`, `for_each` and `depends_on` and removed without orphaning resources. Provider configuration belongs to your
root module, a non-default configuration can be passed with the module's `providers` argument, e.g.
`providers = { proxmox = proxmox.dc2 }`.

The `bpg/proxmox` and `siderolabs/talos` provider versions are constrained to a single minor version, e.g.
`~> 0.111.1`, because pre-1.0 providers ship breaking changes in minor releases. If your root module uses these
providers elsewhere, it must use the same minor version. A module release bumping a provider minor version requires
you to bump it as well.

The `hashicorp/helm` provider is only used to render the Cilium manifest, it never connects to a cluster. If you
configure your default `helm` provider with this module's `kubernetes_client_configuration` output, e.g. for
deploying Helm releases into the new cluster, the module would use that provider too and OpenTofu fails with a
dependency cycle. Pass the module a separate, unconfigured `helm` provider instead:
```hcl
# Only renders the Cilium manifest inside the module, needs no configuration
provider "helm" {
  alias = "render"
}

module "talos_cluster" {
  source = "max-pfeiffer/talos-cluster/proxmox"
  providers = {
    helm = helm.render
  }
  # ...
}

# Deploys Helm releases into the new cluster
provider "helm" {
  kubernetes = {
    host                   = module.talos_cluster.kubernetes_client_configuration.host
    client_certificate     = base64decode(module.talos_cluster.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(module.talos_cluster.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(module.talos_cluster.kubernetes_client_configuration.ca_certificate)
  }
}
```


Nodes in `node_data` are keyed by their IPv4 address. `hostname`, `install_disk` and `install_image` are required,
`cpu_cores`, `memory` (MB), `disk_size` (GB) and `proxmox_node` are optional per node. The `hostname` is used as virtual
machine name, Talos hostname and Kubernetes node name, so all three always match. It must be a unique lowercase
RFC 1123 DNS label of at most 63 characters. Without a `proxmox_node` the virtual machine is created on
`proxmox_target_node`.

At most five control plane nodes are supported. They are configured and upgraded one at a time in numerical IP
order, see [Upgrading Talos](#upgrading-talos). Adding or removing a control plane node with a lower IP address than
existing ones moves those to another position, `tofu plan` then shows their `talos_machine` resources as replaced.
This re-applies the unchanged machine configuration and does not reboot the nodes.

The control plane node with the lowest IP address is used to bootstrap the cluster, run Kubernetes upgrades and
retrieve the kubeconfig. It is chosen once on creation, adding control plane nodes later does not change it. If you
remove that node, move this role to another control plane node:
```shell
tofu apply -replace=module.talos_cluster.talos_cluster.this -replace=module.talos_cluster.talos_cluster_kubeconfig.this
```

Complete examples are in the [examples](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/tree/main/examples) directory:
* [basic](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/tree/main/examples/basic): one control plane and one worker node
* [advanced](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/tree/main/examples/advanced): highly available control plane spread across a Proxmox cluster, VLAN,
  config patches for registry mirrors and additional Cilium Helm values

Apply the configuration and grab the kube config file:
```shell
$ tofu init
$ tofu apply
$ tofu output -raw kubeconfig > ~/.kube/config
$ chmod 600 ~/.kube/config
$ kubectl get nodes
NAME                          STATUS   ROLES           AGE   VERSION
your-cluster-name-cp-0        Ready    control-plane   5d    v1.36.3
your-cluster-name-worker-0    Ready    <none>          5d    v1.36.3
```
You might need to wait a bit until the nodes come up.

<!-- Generated by terraform-docs from variables.tf and outputs.tf, edit those instead -->
<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| proxmox\_target\_node | Name of the Proxmox VE node the virtual machines are created on. Can be overridden per node with `proxmox_node` in `node_data`. | `string` | n/a | yes |
| proxmox\_storage\_device | Proxmox datastore for the virtual machine disks and the cloud-init drives | `string` | n/a | yes |
| proxmox\_iso\_datastore | Proxmox datastore the Talos Linux ISO image is downloaded to, it must support the `iso` content type. Ignored when `talos_linux_iso_file_id` is set. | `string` | `"local"` | no |
| proxmox\_iso\_download\_node | Proxmox node the Talos Linux ISO image is downloaded to once, for a `proxmox_iso_datastore` which is shared by all Proxmox nodes, e.g. NFS or CephFS. By default the image is downloaded to every Proxmox node which hosts a virtual machine. Ignored when `talos_linux_iso_file_id` is set. | `string` | `null` | no |
| proxmox\_network\_bridge | Proxmox network bridge the virtual machines are attached to | `string` | `"vmbr0"` | no |
| vm\_cpu\_type | CPU type emulated for the virtual machines | `string` | `"host"` | no |
| talos\_version | Talos machine configuration contract version. Pin it to the version the cluster was created with, it is independent of the installed Talos version which is driven by `install_image`. Required so that a module upgrade never changes the contract of an existing cluster. At least 1.12 is required for the HostnameConfig document. | `string` | n/a | yes |
| kubernetes\_version | Kubernetes version of the cluster, changing it runs Talos' upgrade-k8s procedure. Required so that a module upgrade never upgrades Kubernetes implicitly. | `string` | n/a | yes |
| talos\_linux\_iso\_image\_url | URL of the Talos ISO image for initially booting the VM. It is downloaded as `talos-<cluster_name>-<URL hash>.iso`. Ignored when `talos_linux_iso_file_id` is set. | `string` | `"https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.13.8/nocloud-amd64.iso"` | no |
| talos\_linux\_iso\_file\_id | ID of an existing Talos ISO image for initially booting the VM, e.g. `local:iso/talos-v1.13.8.iso`, which is managed outside of this module. It must be available on every Proxmox node which hosts a virtual machine. When set, the module does not download the image. | `string` | `null` | no |
| cluster\_name | A name to provide for the Talos cluster | `string` | `"talos"` | no |
| cluster\_vip\_shared\_ip | Shared virtual IP address for control plane nodes, used as Kubernetes API endpoint | `string` | n/a | yes |
| node\_data | Control plane and worker nodes, keyed by the node's IPv4 address. hostname, install\_disk and install\_image are required, cpu\_cores, memory (MB), disk\_size (GB) and proxmox\_node are optional per node. The hostname is used as VM name, Talos hostname and Kubernetes node name, it must be a unique lowercase RFC 1123 DNS label. Without proxmox\_node the VM is created on proxmox\_target\_node. At most five control planes are supported, they are upgraded one at a time in numerical IP order. | ```object({ controlplanes = map(object({ hostname = string install_disk = string install_image = string cpu_cores = optional(number, 2) memory = optional(number, 8192) disk_size = optional(number, 50) proxmox_node = optional(string) })) workers = optional(map(object({ hostname = string install_disk = string install_image = string cpu_cores = optional(number, 2) memory = optional(number, 16384) disk_size = optional(number, 50) proxmox_node = optional(string) })), {}) })``` | n/a | yes |
| network | Network for all nodes in CIDR notation, its prefix length is used for the node IP addresses | `string` | n/a | yes |
| network\_gateway | Network gateway for all nodes | `string` | n/a | yes |
| domain\_name\_servers | DNS servers for all nodes | `list(string)` | n/a | yes |
| vlan\_tag | VLAN tag for all nodes, default does not configure a VLAN | `number` | `0` | no |
| allow\_scheduling\_on\_control\_planes | Allows scheduling of workloads on control plane nodes, e.g. for clusters without worker nodes | `bool` | `false` | no |
| talos\_machine\_config\_patch\_controlplane | Configuration patch which will be applied to all controlplane nodes | `string` | `""` | no |
| talos\_machine\_config\_patch\_worker | Configuration patch which will be applied to all worker nodes | `string` | `""` | no |
| extra\_inline\_manifests | Additional Kubernetes manifests which are applied by Talos on bootstrap, see https://www.talos.dev/latest/reference/configuration/v1alpha1/config/#Config.cluster.inlineManifests | ```list(object({ name = string contents = string }))``` | `[]` | no |
| gateway\_api\_crds\_enabled | Installs the Gateway API v1.6.1 CRDs (standard channel) on bootstrap, required by Cilium's Gateway API support | `bool` | `true` | no |
| cilium\_version | Version of the Cilium Helm chart | `string` | `"1.20.0"` | no |
| cilium\_kubernetes\_compatibility\_check | Fails the plan if the Cilium minor version is not e2e tested with the Kubernetes minor version, see https://docs.cilium.io/en/stable/network/kubernetes/compatibility/. Disable it to run an untested combination deliberately. | `bool` | `true` | no |
| ingress\_controller\_enabled | Enables the Cilium Ingress controller, see https://docs.cilium.io/en/stable/network/servicemesh/ingress/. Disabled by default, the Gateway API supersedes it and its shared LoadBalancer Service takes an address of the LoadBalancer IP pool. | `bool` | `false` | no |
| cilium\_helm\_set | Additional Helm values for Cilium, applied after the module's defaults and cilium\_helm\_values so they override both | ```list(object({ name = string value = string type = optional(string) }))``` | `[]` | no |
| cilium\_helm\_values | Additional Helm values for Cilium as YAML documents, applied in order after the module's defaults so they can override them | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| talosconfig | Talos client configuration for talosctl |
| kubeconfig | Kubeconfig for cluster administration |
| kubernetes\_client\_configuration | Kubernetes API host and client credentials, e.g. for configuring the kubernetes and helm providers. Pass the module a separate helm provider then, see the Providers section of the README. |
| client\_configuration | Talos client configuration (CA certificate, client certificate and key) |
| machine\_secrets | Talos machine secrets of the cluster, keep them safe for disaster recovery |
| cluster\_name | Name of the Talos cluster |
| cluster\_endpoint | Kubernetes API endpoint of the cluster |
| controlplane\_ips | IP addresses of the control plane nodes |
| worker\_ips | IP addresses of the worker nodes |
| controlplane\_vm\_ids | Proxmox VM IDs of the control plane nodes, keyed by IP address |
| worker\_vm\_ids | Proxmox VM IDs of the worker nodes, keyed by IP address |
<!-- END_TF_DOCS -->

## Upgrading
Talos OS and Kubernetes versions are managed declaratively through the
[terraform-provider-talos](https://github.com/siderolabs/terraform-provider-talos) v0.12.0 resources:

* `talos_machine` owns each node's machine configuration and its Talos OS version. On every
  `tofu plan`/`apply` the provider reads the running Talos version, the active Image Factory
  schematic and the applied machine configuration hash from the node and reconciles any drift.
* `talos_cluster` bootstraps etcd and owns the Kubernetes version. Changing its `kubernetes_version`
  runs Talos' `upgrade-k8s` procedure, which pre-pulls images and upgrades kube-apiserver,
  kube-controller-manager, kube-scheduler, kube-proxy and the kubelets sequentially with health
  gating.

Gracefully orchestrating in-place upgrades through Terraform/OpenTofu has long been a rough edge in
the Talos provider — see [siderolabs/terraform-provider-talos#140](https://github.com/siderolabs/terraform-provider-talos/issues/140)
for the multi-year discussion on graceful, node-by-node upgrades.

### Upgrading Talos
1. Pick the new Talos version and update `talos_linux_iso_image_url`, or `talos_linux_iso_file_id` for
   an ISO image managed outside of this module. The new ISO image only affects newly created virtual
   machines.
2. For every node in `node_data`, update `install_image` to the matching version tag, e.g.
   `factory.talos.dev/nocloud-installer/<schematic-id>:v1.14.0`. The schematic ID stays the same
   across versions unless you change the extensions baked into the image on the
   [Talos Image Factory](https://factory.talos.dev/); only the version tag needs bumping.
   `install_image` alone drives the OS upgrade.
3. Leave `talos_version` alone. It is the *machine configuration contract*, pinned to the version the
   cluster was created with, and is independent of the installed Talos version — the provider's docs
   make this [explicit](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration)
   as of v0.12.0. Bumping it regenerates every node's machine configuration with the new contract's
   schema and defaults, which is a separate, deliberate action, not part of a routine OS upgrade.
4. Run `tofu plan` to confirm only the `image` field (and any machine config drift) is changing, not
   disk layout or network settings.
5. Run `tofu apply`. Control plane nodes are upgraded one at a time in numerical IP order, following
   the provider's
   [Upgrading multiple nodes safely](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine#upgrading-multiple-nodes-safely)
   guidance: every node is drained, rebooted and back with a healthy etcd member before the next one
   starts, so etcd keeps its quorum. Worker nodes are upgraded in parallel. To upgrade them one at a
   time as well, run `tofu apply -parallelism=1`, or bump `install_image` for a few workers per apply.
6. `drain_on_upgrade` is `true` for all `talos_machine` resources, so each node is cordoned and
   drained before it reboots and uncordoned afterwards. The kubeconfig needed for that is derived
   offline from the machine secrets by an ephemeral `talos_cluster_kubeconfig` resource, which keeps it
   free of a dependency cycle with `talos_machine` and out of the state. Draining requires a healthy
   Kubernetes cluster, so keep the ISO version and `install_image` in step (1)/(2) in sync: an upgrade
   that fires during the *initial* bring-up, before Kubernetes exists, would fail on the drain.

### Upgrading Kubernetes
1. Update `kubernetes_version`.
2. The value feeds both `talos_cluster` and the generated machine configuration. `talos_cluster`
   performs the actual rolling upgrade via `upgrade-k8s`; the machine configuration only controls the
   image tags baked into it, which matter at bootstrap when a node is added later, so the two must stay
   in sync — a single variable feeds both.
3. All `talos_machine` resources set `ignore_kubernetes_upgrade_drift = true`, so the five
   Kubernetes component image fields owned by `upgrade-k8s` (`machine.kubelet.image`,
   `cluster.apiServer.image`, `cluster.controllerManager.image`, `cluster.scheduler.image`,
   `cluster.proxy.image`) are excluded from `talos_machine`'s drift detection. Without it,
   `tofu apply` would re-apply those tags directly and in parallel across all nodes, bypassing
   `upgrade-k8s`'s sequencing. Note that the attribute is flagged experimental by the provider: only
   the version tag is stripped from the hash, so a registry change is still detected as drift.
4. A plain `tofu apply` is safe here — `talos_cluster` does the sequencing and health gating itself,
   so `-parallelism=1` is not needed for this step.

### Changing the Cilium configuration
Cilium is installed as a Talos inline manifest. Talos only creates missing resources of inline manifests, it never
updates or deletes existing ones, so changing a Cilium input like `ingress_controller_enabled` or `cilium_helm_set`
only changes the machine configuration of the control plane nodes. Synchronize the manifests of a running cluster
afterwards with Talos' Kubernetes upgrade procedure and the current Kubernetes version, which also prunes removed
resources (Talos >= v1.13, talosctl must match the Talos version). The Cilium pods carry a checksum of their
configuration, so they roll out automatically when it changes:
```shell
talosctl -n <control plane node> upgrade-k8s --to <current Kubernetes version> --dry-run
talosctl -n <control plane node> upgrade-k8s --to <current Kubernetes version>
```

The module's Cilium defaults are the first Helm values document. `cilium_helm_values` are applied after them in
order, `cilium_helm_set` is applied last and overrides both.

### Cilium and Kubernetes compatibility
The plan fails if the Cilium minor version is not e2e tested with the Kubernetes minor version according to the
[Cilium compatibility matrix](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/), e.g. Cilium 1.20
supports Kubernetes 1.33 to 1.36. Upgrade Cilium before moving to a Kubernetes minor version it does not support yet.
Set `cilium_kubernetes_compatibility_check = false` to run an untested combination deliberately.

## Versioning
The module follows [Semantic Versioning](https://semver.org/), releases are tagged `vX.Y.Z` and created by
[release-please](https://github.com/googleapis/release-please) from [Conventional Commits](https://www.conventionalcommits.org/).
While the module is below `1.0.0`, breaking changes bump the minor version and everything else the patch version.
Pin the module to an exact `version` and read the [changelog](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/blob/main/CHANGELOG.md) before upgrading.

A change is breaking (`feat!:` or a `BREAKING CHANGE:` footer) if it changes infrastructure that existing users get
on their next `tofu apply` without touching their configuration, in particular:
* changing the default of any version input, e.g. `cilium_version`, `talos_linux_iso_image_url` or the bundled
  Gateway API CRDs
* removing or renaming inputs or outputs, adding required inputs or changing their types
* changing resource addresses without `moved` blocks
* raising the minimum OpenTofu or provider versions

## Development
Install [uv](https://docs.astral.sh/uv/getting-started/installation/), [OpenTofu](https://opentofu.org/docs/intro/install/),
[TFLint](https://github.com/terraform-linters/tflint) and [terraform-docs](https://terraform-docs.io/), e.g. on macOS:
```shell
brew install uv opentofu terraform-docs terraform-linters/tap/tflint
```
TFLint is not available in Homebrew's core repository, it is installed from the
[official TFLint tap](https://github.com/terraform-linters/homebrew-tap). For other platforms see the
[TFLint installation instructions](https://github.com/terraform-linters/tflint#installation).

Sync dependencies and install the git hooks:
```shell
uv sync
uv run pre-commit install
```
The hooks format and lint the code, generate the inputs and outputs in this README, lint the GitHub workflows and check
commit messages and pushed commits for secrets.

Commit messages and pull request titles must follow [Conventional Commits](https://www.conventionalcommits.org/),
both are checked in CI. Pull requests are squash merged with their title as commit message.

Validate and test the module, the tests use mocked providers and need neither Proxmox nor a Talos cluster:
```shell
tofu init -backend=false
tofu validate
tofu test
```

## Information Sources
* [Talos Linux documentation](https://www.talos.dev/)
* [Talos Linux Image Factory](https://factory.talos.dev/)
* [Cilium documentation](https://docs.cilium.io/en/stable/)
* [Gateway API](https://gateway-api.sigs.k8s.io/)
* Terraform providers:
  * [terraform-provider-proxmox](https://github.com/bpg/terraform-provider-proxmox)
  * [terraform-provider-talos](https://github.com/siderolabs/terraform-provider-talos)
  * [terraform-provider-helm](https://github.com/hashicorp/terraform-provider-helm)
* Helm charts:
  * [Cilium](https://artifacthub.io/packages/helm/cilium/cilium)
