resource "kubectl_manifest" "teleport_node_token" {
  yaml_body = yamlencode(
    {
      apiVersion = "resources.teleport.dev/v2"
      kind       = "TeleportProvisionToken"

      metadata = {
        name      = "teleport-demo-nodes"
        namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
      }

      spec = {
        roles       = ["Node"]
        join_method = "kubernetes"
        kubernetes = {
          type = "in_cluster"
          allow = [
            {
              service_account = "${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}:teleport-demo-node"
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
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }

  data = {
    "teleport.yaml" = yamlencode({
      version = "v3"
      teleport = {
        proxy_server = "${local.teleport_cluster_fqdn}:443"
        diag_addr    = "0.0.0.0:3000"
        join_params = {
          method     = "kubernetes"
          token_name = "teleport-demo-nodes"
        }
      }
      auth_service = {
        enabled = false
      }
      proxy_service = {
        enabled = false
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
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
}

locals {
  node_definitions = {
    rocky9 = {
      image = local.node_image_names["rocky9"]
      teleport_labels = {
        distro_family = "rhel"
        mascot        = "Rocky Raccoon"
        founded       = "2021"
        pkg_mgr       = "dnf"
        init          = "systemd"
      }
    }
    rocky8 = {
      image = local.node_image_names["rocky8"]
      teleport_labels = {
        distro_family = "rhel"
        mascot        = "Rocky Raccoon"
        founded       = "2021"
        pkg_mgr       = "dnf"
        init          = "systemd"
      }
    }
    fedora43 = {
      image = local.node_image_names["fedora43"]
      teleport_labels = {
        distro_family = "rhel"
        mascot        = "Fedora Bead"
        founded       = "2003"
        pkg_mgr       = "dnf"
        init          = "systemd"
      }
    }
    al2023 = {
      image = local.node_image_names["al2023"]
      teleport_labels = {
        distro_family = "rhel"
        mascot        = "Peccy the Penguin"
        founded       = "2023"
        pkg_mgr       = "dnf"
        cloud         = "aws"
      }
    }
    ubuntu2404 = {
      image = local.node_image_names["ubuntu2404"]
      teleport_labels = {
        hostname      = "ubuntu2404"
        distro_family = "debian"
        mascot        = "Noble Numbat"
        founded       = "2004"
        pkg_mgr       = "apt"
        default_shell = "bash"
      }
    }
    ubuntu2204 = {
      image = local.node_image_names["ubuntu2204"]
      teleport_labels = {
        distro_family = "debian"
        mascot        = "Jammy Jellyfish"
        founded       = "2004"
        pkg_mgr       = "apt"
        default_shell = "bash"
      }
    }
    debian12 = {
      image = local.node_image_names["debian12"]
      teleport_labels = {
        distro_family = "debian"
        mascot        = "Bookworm"
        founded       = "1993"
        pkg_mgr       = "apt"
        philosophy    = "free-as-in-freedom"
      }
    }
    alpine321 = {
      image = local.node_image_names["alpine321"]
      teleport_labels = {
        distro_family = "independent"
        mascot        = "Alpine Ibex"
        founded       = "2005"
        pkg_mgr       = "apk"
        libc          = "musl"
      }
    }
    opensuse16 = {
      image = local.node_image_names["opensuse16"]
      teleport_labels = {
        distro_family = "suse"
        mascot        = "Geeko the Chameleon"
        founded       = "2005"
        pkg_mgr       = "zypper"
        init          = "systemd"
      }
    }
    archlinux = {
      image = local.node_image_names["archlinux"]
      teleport_labels = {
        distro_family = "independent"
        mascot        = "Archie"
        founded       = "2002"
        pkg_mgr       = "pacman"
        philosophy    = "keep-it-simple"
      }
    }
  }
}

module "teleport_nodes" {
  source = "./module/teleport_node"

  namespace            = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  configmap_name       = kubernetes_config_map.teleport_node_config.metadata[0].name
  service_account_name = kubernetes_service_account.teleport_demo_node.metadata[0].name

  nodes = {
    for name, cfg in local.node_definitions : name => {
      name            = name
      image           = cfg.image
      teleport_labels = cfg.teleport_labels
    }
  }

  depends_on = [
    helm_release.teleport_cluster,
    kubectl_manifest.teleport_node_token,
  ]
}
