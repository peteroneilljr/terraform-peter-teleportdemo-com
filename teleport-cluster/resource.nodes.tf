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
    pacman = {
      image = local.node_image_names["pacman"]
      teleport_labels = {
        access = "restricted"
      }
    }
    tetris = {
      image = local.node_image_names["tetris"]
      teleport_labels = {
        access = "restricted"
      }
    }
  }
}

resource "kubernetes_deployment" "teleport_node" {
  for_each = local.node_definitions

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
    labels = {
      app = each.key
    }
  }

  wait_for_rollout = false

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = each.key
      }
    }

    template {
      metadata {
        labels = {
          app = each.key
        }
      }

      spec {
        service_account_name = kubernetes_service_account.teleport_demo_node.metadata[0].name
        hostname             = each.key

        container {
          name              = each.key
          image             = each.value.image
          image_pull_policy = "Always"
          command           = ["teleport", "start", "-c", "/etc/teleport.yaml"]
          args              = length(each.value.teleport_labels) > 0 ? ["--labels=${join(",", [for k, v in each.value.teleport_labels : "${k}=${v}"])}"] : []

          liveness_probe {
            http_get {
              path = "/readyz"
              port = 3000
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "teleport-config"
            mount_path = "/etc/teleport.yaml"
            sub_path   = "teleport.yaml"
            read_only  = true
          }
        }

        volume {
          name = "teleport-config"
          config_map {
            name = kubernetes_config_map.teleport_node_config.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.teleport_cluster,
    kubectl_manifest.teleport_node_token,
  ]
}
