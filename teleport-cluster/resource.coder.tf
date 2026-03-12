resource "kubernetes_namespace_v1" "coder" {
  metadata { name = "coder" }
}

resource "kubernetes_secret_v1" "coder_db_url" {
  metadata {
    name      = "coder-db-url"
    namespace = kubernetes_namespace_v1.coder.metadata[0].name
  }
  data = {
    url = "postgres://coder:${random_password.coder_db.result}@${module.postgres.helm_release_name}-postgresql.${module.postgres.helm_release_namespace}.svc.cluster.local:5432/coder?sslmode=require"
  }
}

resource "helm_release" "coder" {
  name       = "coder"
  namespace  = kubernetes_namespace_v1.coder.metadata[0].name
  repository = "https://helm.coder.com/v2"
  chart      = "coder"

  wait = false

  values = [yamlencode({
    coder = {
      resources = {
        requests = { cpu = "1000m", memory = "2Gi" }
      }
      service = { type = "ClusterIP" }
      env = [
        { name = "CODER_PG_CONNECTION_URL", valueFrom = { secretKeyRef = { name = kubernetes_secret_v1.coder_db_url.metadata[0].name, key = "url" } } },
        { name = "CODER_ACCESS_URL", value = "https://coder.${local.teleport_cluster_fqdn}" },
        { name = "CODER_WILDCARD_ACCESS_URL", value = "*.coder.${local.teleport_cluster_fqdn}" },
      ]
    }
  })]

  depends_on = [kubernetes_secret_v1.coder_db_url]
}

resource "kubectl_manifest" "teleport_role_coder" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "${var.resource_prefix}coder"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        app_labels = {
          app = "coder"
        }
      }
    }
  })
}

resource "kubernetes_cluster_role_binding" "coder" {
  metadata { name = "coder-workspace-manager" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "coder"
    namespace = kubernetes_namespace_v1.coder.metadata[0].name
  }
}
