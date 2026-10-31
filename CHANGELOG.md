# Changelog

## [0.4.0](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/compare/v0.3.0...v0.4.0) (2026-10-31)


### ⚠ BREAKING CHANGES

* **deps:** bump cilium to 1.20.4 and gateway api to v1.6.3 and added version mappings

### Features

* **deps:** bump cilium to 1.20.4 and gateway api to v1.6.3 and added version mappings ([c7bb1f3](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/c7bb1f3effbc7f7459e249939981985e2b830a20))

## [0.3.0](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/compare/v0.2.0...v0.3.0) (2026-10-31)


### ⚠ BREAKING CHANGES

* download gateway api crds instead of bundling them
* check cilium kubernetes compatibility and roll out config changes

### Features

* check cilium kubernetes compatibility and roll out config changes ([301b886](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/301b88619cb746fc9eb6c590c89199c34f779029))
* download gateway api crds instead of bundling them ([0b9cd34](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/0b9cd34230e06d4ed09a9ab3a60679931e783967))
* improve cilium config ([2814daf](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/2814dafae41855d7149b91ff4c2f96ed9d3e8e34))
* ingress controller is disabled by default ([0dcc020](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/0dcc02077644ca8739542b6c8201fdd7e1358478))

## [0.2.0](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/compare/v0.1.0...v0.2.0) (2026-10-31)


### ⚠ BREAKING CHANGES

* upgrade control plane nodes sequentially
* simplified hostname handling
* stable VM names, pinned bootstrap node and default route

### Features

* improved talos iso handling ([f904873](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/f9048737e59f4f065feed9eced5a30b461ed0f4b))
* simplified hostname handling ([90b8af8](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/90b8af8f5c9d046f1ba3f91ecd50506f4ba1dcd7))
* stable VM names, pinned bootstrap node and default route ([a7b2b8b](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/a7b2b8be71f3065a8f99a99ff9b0b761fe5389f1))
* upgrade control plane nodes sequentially ([a1fa8d8](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/a1fa8d877a715f618faf75c2ff6dfcd5fe0e089a))


### Bug Fixes

* provider setup ([25b8b4f](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/25b8b4f4bb4ca63c662a9c1a044b54e3e3e073a5))

## 0.1.0 (2026-10-09)


### Features

* initial module setup ([81c823c](https://github.com/max-pfeiffer/terraform-proxmox-talos-cluster/commit/81c823c5d6fdda82891d5e0b71f1d030fee67baf))
