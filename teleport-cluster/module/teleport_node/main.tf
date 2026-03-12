resource "kubernetes_deployment" "this" {
  for_each = var.nodes

  metadata {
    name      = each.value.name
    namespace = var.namespace
    labels = {
      app = each.value.name
    }
  }

  wait_for_rollout = each.value.wait_for_rollout

  spec {
    replicas = each.value.replicas

    selector {
      match_labels = {
        app = each.value.name
      }
    }

    template {
      metadata {
        labels = {
          app = each.value.name
        }
      }

      spec {
        service_account_name = var.service_account_name
        hostname             = each.value.name

        container {
          name              = each.value.name
          image             = each.value.image
          image_pull_policy = "Always"
          command           = ["teleport", "start", "-c", "/etc/teleport.yaml"]
          args    = length(each.value.teleport_labels) > 0 ? ["--labels=${join(",", [for k, v in each.value.teleport_labels : "${k}=${v}"])}"] : []

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
            name = var.configmap_name
          }
        }
      }
    }
  }
}
