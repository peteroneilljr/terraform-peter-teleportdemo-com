resource "kubectl_manifest" "teleport_node_token" {
  yaml_body = yamlencode(
    {
      apiVersion = "resources.teleport.dev/v2"
      kind       = "TeleportProvisionToken"

      metadata = {
        name      = "teleport-demo-nodes"
        namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0]
      }

      spec = {
        roles       = ["Node"]
        join_method = "kubernetes"
        kubernetes = {
          type = "in_cluster"
          allow = [
            {
              service_account = "${kubernetes_namespace_v1.teleport_cluster.metadata[0]}:teleport-demo-node"
            }
          ]
        }
      }
    }
  )

  depends_on = [
    helm_release.teleport_cluster
  ]
}

resource "kubernetes_config_map" "teleport_node_config" {
  metadata {
    name      = "teleport-node-config"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0]
  }

  data = {
    "teleport.yaml" = yamlencode({
      version = "v3"
      teleport = {
        proxy_server = "${local.teleport_cluster_fqdn}:443"
        join_params = {
          method     = "kubernetes"
          token_name = "teleport-demo-nodes"
        }
      }
      ssh_service = {
        enabled = true
      }
    })
  }
}

resource "kubernetes_service_account" "teleport_demo_node" {
  metadata {
    name      = "teleport-demo-node"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0]
  }
}

locals {
  node_definitions = {
    rocky9     = { image = local.node_image_names["rocky9"] }
    rocky8     = { image = local.node_image_names["rocky8"] }
    fedora43   = { image = local.node_image_names["fedora43"] }
    al2023     = { image = local.node_image_names["al2023"] }
    ubuntu2404 = { image = local.node_image_names["ubuntu2404"] }
    ubuntu2204 = { image = local.node_image_names["ubuntu2204"] }
    debian12   = { image = local.node_image_names["debian12"] }
    alpine321  = { image = local.node_image_names["alpine321"] }
    opensuse16 = { image = local.node_image_names["opensuse16"] }
    archlinux  = { image = local.node_image_names["archlinux"] }
  }
}

module "teleport_nodes" {
  source = "./module/teleport_node"

  namespace            = kubernetes_namespace_v1.teleport_cluster.metadata[0]
  configmap_name       = kubernetes_config_map.teleport_node_config.metadata[0]
  service_account_name = kubernetes_service_account.teleport_demo_node.metadata[0]

  nodes = {
    for name, cfg in local.node_definitions : name => {
      name  = name
      image = cfg.image
    }
  }

  depends_on = [
    helm_release.teleport_cluster,
    kubectl_manifest.teleport_node_token,
  ]
}
