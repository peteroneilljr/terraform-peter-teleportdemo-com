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
  teleport_tarball_url = "https://cdn.teleport.dev/teleport-v${var.teleport_version}-linux-amd64-bin.tar.gz"

  # Common install snippets
  apt_install_teleport = "apt-get update && apt-get install -y --no-install-recommends curl sudo ca-certificates && curl -sLO ${local.teleport_tarball_url} && tar xf *.tar.gz && ./teleport/install && rm -rf teleport *.tar.gz"
  dnf_install_teleport = "dnf install -y sudo tar && curl -sLO ${local.teleport_tarball_url} && tar xf *.tar.gz && ./teleport/install && rm -rf teleport *.tar.gz"

  node_definitions = {
    debian12 = {
      image       = "debian:12"
      install_cmd = local.apt_install_teleport
      teleport_labels = {
        distro_family = "debian"
        mascot        = "Bookworm"
        founded       = "1993"
        pkg_mgr       = "apt"
        philosophy    = "free-as-in-freedom"
      }
    }
    ubuntu2404 = {
      image       = "ubuntu:24.04"
      install_cmd = local.apt_install_teleport
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
      image       = "ubuntu:22.04"
      install_cmd = local.apt_install_teleport
      teleport_labels = {
        distro_family = "debian"
        mascot        = "Jammy Jellyfish"
        founded       = "2004"
        pkg_mgr       = "apt"
        default_shell = "bash"
      }
    }
    rocky9 = {
      image       = "rockylinux:9"
      install_cmd = local.dnf_install_teleport
      teleport_labels = {
        distro_family = "rhel"
        mascot        = "Rocky Raccoon"
        founded       = "2021"
        pkg_mgr       = "dnf"
        init          = "systemd"
      }
    }
    rocky8 = {
      image       = "rockylinux:8"
      install_cmd = local.dnf_install_teleport
      teleport_labels = {
        distro_family = "rhel"
        mascot        = "Rocky Raccoon"
        founded       = "2021"
        pkg_mgr       = "dnf"
        init          = "systemd"
      }
    }
    fedora43 = {
      image       = "fedora:43"
      install_cmd = local.dnf_install_teleport
      teleport_labels = {
        distro_family = "rhel"
        mascot        = "Fedora Bead"
        founded       = "2003"
        pkg_mgr       = "dnf"
        init          = "systemd"
      }
    }
    al2023 = {
      image       = "amazonlinux:2023"
      install_cmd = "dnf install -y sudo tar gzip && curl -sLO ${local.teleport_tarball_url} && tar xf *.tar.gz && ./teleport/install && rm -rf teleport *.tar.gz"
      teleport_labels = {
        distro_family = "rhel"
        mascot        = "Peccy the Penguin"
        founded       = "2023"
        pkg_mgr       = "dnf"
        cloud         = "aws"
      }
    }
    opensuse16 = {
      image       = "opensuse/leap:16.0"
      install_cmd = "zypper install -y sudo curl tar gzip && curl -sLO ${local.teleport_tarball_url} && tar xf *.tar.gz && ./teleport/install && rm -rf teleport *.tar.gz"
      teleport_labels = {
        distro_family = "suse"
        mascot        = "Geeko the Chameleon"
        founded       = "2005"
        pkg_mgr       = "zypper"
        init          = "systemd"
      }
    }
    archlinux = {
      image       = "archlinux:latest"
      install_cmd = "pacman -Sy --noconfirm sudo curl tar && curl -sLO ${local.teleport_tarball_url} && tar xf *.tar.gz && ./teleport/install && rm -rf teleport *.tar.gz"
      teleport_labels = {
        distro_family = "independent"
        mascot        = "Archie"
        founded       = "2002"
        pkg_mgr       = "pacman"
        philosophy    = "keep-it-simple"
      }
    }
    tetris = {
      image       = "debian:12"
      install_cmd = "apt-get update && apt-get install -y --no-install-recommends curl sudo ca-certificates bastet && echo '[ -t 0 ] && exec /usr/games/bastet' >> /root/.profile && curl -sLO ${local.teleport_tarball_url} && tar xf *.tar.gz && ./teleport/install && rm -rf teleport *.tar.gz"
      teleport_labels = {
        access = "restricted"
      }
    }
    pacman = {
      image       = "debian:12"
      install_cmd = "apt-get update && apt-get install -y --no-install-recommends curl sudo ca-certificates build-essential libncurses-dev git && git clone --depth 1 https://github.com/kragen/myman.git /tmp/myman && cd /tmp/myman && ./configure --disable-variants && make -j$(nproc) && make install && cd / && rm -rf /tmp/myman && echo '[ -t 0 ] && exec myman -z big' >> /root/.profile && curl -sLO ${local.teleport_tarball_url} && tar xf *.tar.gz && ./teleport/install && rm -rf teleport *.tar.gz"
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
          image_pull_policy = "IfNotPresent"
          command           = ["/bin/sh", "-c"]
          args = [
            "${each.value.install_cmd} && exec teleport start -c /etc/teleport.yaml ${length(each.value.teleport_labels) > 0 ? "'--labels=${join(",", [for k, v in each.value.teleport_labels : "${k}=${v}"])}'" : ""}"
          ]

          liveness_probe {
            http_get {
              path = "/readyz"
              port = 3000
            }
            initial_delay_seconds = 180
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 3000
            }
            initial_delay_seconds = 120
            period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
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
