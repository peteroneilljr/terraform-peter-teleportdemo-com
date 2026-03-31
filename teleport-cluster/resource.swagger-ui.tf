# Swagger UI — default Petstore spec, served by kube-agent

resource "kubernetes_deployment_v1" "swagger_ui" {
  metadata {
    name      = "${var.resource_prefix}swagger-ui"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
    labels    = { app = "swagger-ui" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "swagger-ui" }
    }

    template {
      metadata {
        labels = { app = "swagger-ui" }
      }

      spec {
        container {
          name  = "swagger-ui"
          image = "swaggerapi/swagger-ui"

          port {
            container_port = 8080
          }

          resources {
            requests = {
              memory = "64Mi"
              cpu    = "10m"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "swagger_ui" {
  metadata {
    name      = "${var.resource_prefix}swagger-ui"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
    labels    = { app = "swagger-ui" }
  }

  spec {
    selector = { app = "swagger-ui" }
    type     = "ClusterIP"

    port {
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubectl_manifest" "teleport_role_swagger_ui" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "${var.resource_prefix}swagger-ui"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        app_labels = {
          app = "swagger-ui"
        }
      }
    }
  })
}
