resource "random_string" "teleport_node_token" {
  length  = 32
  special = false
  upper   = false
  lower   = true
}


resource "kubectl_manifest" "teleport_node_token" {
  yaml_body = yamlencode(
    {
      apiVersion = "resources.teleport.dev/v2"
      kind       = "TeleportProvisionToken"

      metadata = {
        name      = random_string.teleport_node_token.result
        namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
      }

      spec = {
        roles       = ["Node"]
        join_method = "token"

      }
    }
  )

  depends_on = [
    helm_release.teleport_cluster
  ]
}

locals {
  teleport_managed_updates_entrypoint_sh = <<-EOT
    curl -o teleport-update.tgz https://cdn.teleport.dev/teleport-update-v${var.teleport_version}-linux-amd64-bin.tar.gz && \
    tar xf teleport-update.tgz && cd ./teleport && \
    ./teleport-update enable --proxy ${local.teleport_cluster_fqdn} && \
    /usr/local/bin/teleport start --roles=node --auth-server=${local.teleport_cluster_fqdn}:443 --token=${random_string.teleport_node_token.result}
  EOT
  pkg_entrypoint = {
    pacman = <<-EOT
      pacman -Syu sudo --noconfirm && \
      ${local.teleport_managed_updates_entrypoint_sh}
    EOT
    apt    = <<-EOT
      apt-get update && \
      apt-get install -y curl sudo && \
      ${local.teleport_managed_updates_entrypoint_sh}
    EOT
    dnf    = <<-EOT
      dnf update -y && \
      dnf install -y sudo && \
      ${local.teleport_managed_updates_entrypoint_sh}
    EOT
  }
  node_definitions = {
    rocky9     = { image = "rockylinux:9", pkg = "dnf" }
    rocky8     = { image = "rockylinux:8", pkg = "dnf" }
    fedora43   = { image = "fedora:43", pkg = "dnf" }
    fedora42   = { image = "fedora:42", pkg = "dnf" }
    ubuntu2404 = { image = "ubuntu:24.04", pkg = "apt" }
    ubuntu2204 = { image = "ubuntu:22.04", pkg = "apt" }
    ubuntu1604 = { image = "ubuntu:16.04", pkg = "apt" }
    debian11   = { image = "debian:11", pkg = "apt" }
    debian12   = { image = "debian:12", pkg = "apt" }
    archlinux  = { image = "archlinux:latest", pkg = "pacman" }
  }
}

module "teleport_nodes" {
  source = "./module/teleport_node"

  nodes = {
    for name, cfg in local.node_definitions : name => {
      name      = name
      namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
      image     = cfg.image
      command   = ["/bin/bash", "-c"]
      args      = [local.pkg_entrypoint[cfg.pkg]]
    }
  }

  depends_on = [
    helm_release.teleport_cluster
  ]
}
