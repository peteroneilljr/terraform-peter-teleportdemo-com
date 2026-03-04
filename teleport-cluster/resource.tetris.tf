locals {
  tetris_entrypoint = <<-EOT
    apt-get update && \
    apt-get install -y curl sudo bastet && \
    echo '[ -t 0 ] && exec /usr/games/bastet' >> /root/.profile && \
    ${local.teleport_managed_updates_entrypoint_sh}
  EOT
}

module "tetris_node" {
  source = "./module/teleport_node"

  nodes = {
    tetris = {
      name      = "tetris"
      namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
      image     = "debian:12"
      command   = ["/bin/bash", "-c"]
      args      = [local.tetris_entrypoint]
    }
  }

  depends_on = [
    helm_release.teleport_cluster
  ]
}
