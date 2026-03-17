resource "kubectl_manifest" "teleport_app_grafana" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "grafana"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s" }
    }
    spec = {
      uri         = "http://${helm_release.grafana.name}.${helm_release.grafana.namespace}.svc.cluster.local"
      public_addr = "grafana.${local.teleport_cluster_fqdn}"
    }
  })
}

resource "kubectl_manifest" "teleport_app_argocd" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "argocd"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s", app = "argocd" }
    }
    spec = {
      uri                  = "https://${helm_release.argocd.name}-server.${helm_release.argocd.namespace}.svc.cluster.local"
      public_addr          = "argocd.${local.teleport_cluster_fqdn}"
      insecure_skip_verify = true
      rewrite = {
        headers = [
          { name = "Teleport-Jwt-Assertion", value = "" }
        ]
      }
    }
  })
}

resource "kubectl_manifest" "teleport_app_awsconsole" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "awsconsole"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s", app = "aws" }
    }
    spec = {
      uri = "https://console.aws.amazon.com/"
    }
  })
}

resource "kubectl_manifest" "teleport_app_awsconsole_bedrock" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "awsconsole-bedrock"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { app = "bedrock" }
    }
    spec = {
      uri = "https://console.aws.amazon.com/bedrock"
    }
  })
}

resource "kubectl_manifest" "teleport_app_coder" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "coder"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s", app = "coder" }
    }
    spec = {
      uri         = "http://coder.${helm_release.coder.namespace}.svc.cluster.local"
      public_addr = "coder.${local.teleport_cluster_fqdn}"
      rewrite = {
        headers = [
          { name = "Host", value = "coder.${local.teleport_cluster_fqdn}" }
        ]
      }
    }
  })
}

resource "kubectl_manifest" "teleport_app_elasticsearch" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "elasticsearch"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s", app = "elasticsearch" }
    }
    spec = {
      uri                  = "https://${helm_release.elasticsearch.name}-master.${helm_release.elasticsearch.namespace}.svc.cluster.local:9200"
      public_addr          = "elasticsearch.${local.teleport_cluster_fqdn}"
      insecure_skip_verify = true # auto-generated internal TLS certs
      # Inject basic auth so users skip the ES login prompt (Teleport handles real auth)
      rewrite = {
        headers = [
          {
            name  = "Authorization"
            value = "Basic ${base64encode("elastic:${random_password.elasticsearch.result}")}"
          }
        ]
      }
    }
  })
}

resource "kubectl_manifest" "teleport_app_kibana" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "kibana"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s", app = "kibana" }
    }
    spec = {
      uri         = "http://${kubernetes_service_v1.kibana.metadata[0].name}.${kubernetes_service_v1.kibana.metadata[0].namespace}.svc.cluster.local:5601"
      public_addr = "kibana.${local.teleport_cluster_fqdn}"
    }
  })
}

resource "kubectl_manifest" "teleport_app_swagger_ui" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "swagger-ui"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s", app = "swagger-ui" }
    }
    spec = {
      uri         = "http://${kubernetes_service_v1.swagger_ui.metadata[0].name}.${kubernetes_namespace_v1.apps.metadata[0].name}.svc.cluster.local:8080"
      public_addr = "swagger-ui.${local.teleport_cluster_fqdn}"
    }
  })
}
