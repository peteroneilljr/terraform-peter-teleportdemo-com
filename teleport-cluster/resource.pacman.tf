module "pacman_node" {
  source = "./module/teleport_node"

  namespace            = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  configmap_name       = kubernetes_config_map.teleport_node_config.metadata[0].name
  service_account_name = kubernetes_service_account.teleport_demo_node.metadata[0].name

  nodes = {
    pacman = {
      name  = "pacman"
      image = local.node_image_names["pacman"]
      teleport_labels = {
        access = "restricted"
      }
    }
  }

  depends_on = [
    helm_release.teleport_cluster,
    kubectl_manifest.teleport_node_token,
  ]
}
