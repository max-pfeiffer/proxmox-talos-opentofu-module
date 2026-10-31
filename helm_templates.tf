locals {
  # Kubernetes minor versions which are e2e tested per Cilium minor version, see
  # https://docs.cilium.io/en/v<Cilium minor version>/network/kubernetes/compatibility/
  # Add the new Cilium minor version here before bumping the cilium_version default.
  cilium_kubernetes_compatibility = {
    "1.19" = ["1.32", "1.33", "1.34", "1.35"]
    "1.20" = ["1.33", "1.34", "1.35", "1.36"]
  }
  cilium_minor_version     = join(".", regex("^v?(\\d+)\\.(\\d+)", var.cilium_version))
  kubernetes_minor_version = join(".", regex("^v?(\\d+)\\.(\\d+)", var.kubernetes_version))

  # Module defaults for the Cilium Helm chart, the first values document so that cilium_helm_values
  # and cilium_helm_set can override them
  cilium_values = merge(
    {
      ipam = {
        mode = "kubernetes"
      }
      kubeProxyReplacement = true
      securityContext = {
        capabilities = {
          ciliumAgent      = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
          cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
        }
      }
      cgroup = {
        autoMount = {
          enabled = false
        }
        hostRoot = "/sys/fs/cgroup"
      }
      k8sServiceHost = "localhost"
      k8sServicePort = 7445
      # L2 Loadbalancer
      # See: https://docs.cilium.io/en/stable/network/l2-announcements/
      l2announcements = {
        enabled = true
      }
      k8sClientRateLimit = {
        qps   = 50
        burst = 100
      }
      # Gateway API
      # See: https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
      gatewayAPI = {
        enabled           = var.gateway_api_enabled
        enableAlpn        = true
        enableAppProtocol = true
        gatewayClass = {
          create = "true"
        }
      }
      # Generate Hubble TLS certificates in-cluster with a CronJob instead of at Helm render time,
      # otherwise every render produces new certificates and the machine config never converges
      # See: https://docs.cilium.io/en/stable/observability/hubble/configuration/tls/
      hubble = {
        tls = {
          auto = {
            method = "cronJob"
          }
        }
      }
      # Egress Gateway
      # See: https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/
      egressGateway = {
        enabled = true
      }
      bpf = {
        masquerade = true
      }
      # Restart the pods when their configuration changes, Talos syncs the manifests but never restarts them
      rollOutCiliumPods = true
      operator = {
        rollOutPods = true
        # The replicas avoid sharing a node, a second replica stays pending on a single node cluster
        replicas = min(2, length(var.node_data.controlplanes) + length(var.node_data.workers))
      }
      envoy = {
        rollOutPods = true
      }
    },
    # Ingress Controller
    # See: https://docs.cilium.io/en/stable/network/servicemesh/ingress/
    var.ingress_controller_enabled ? {
      ingressController = {
        enabled          = true
        loadbalancerMode = "dedicated"
      }
    } : {},
  )
}

data "helm_template" "cilium" {
  name         = "cilium"
  namespace    = "kube-system"
  repository   = "https://helm.cilium.io"
  chart        = "cilium"
  version      = var.cilium_version
  kube_version = var.kubernetes_version
  values       = concat([yamlencode(local.cilium_values)], var.cilium_helm_values)
  set          = var.cilium_helm_set

  # The chart only declares a minimum Kubernetes version, so kube_version never rejects a too new one
  lifecycle {
    precondition {
      condition = !var.cilium_kubernetes_compatibility_check || contains(
        lookup(local.cilium_kubernetes_compatibility, local.cilium_minor_version, []),
        local.kubernetes_minor_version,
      )
      error_message = "Cilium ${var.cilium_version} is not tested with Kubernetes ${var.kubernetes_version}, see https://docs.cilium.io/en/v${local.cilium_minor_version}/network/kubernetes/compatibility/. Set cilium_kubernetes_compatibility_check = false to skip this check."
    }
  }
}
