resource "kubernetes_secret" "sso_github" {
  metadata {
    name      = "${var.resource_prefix}github-oauth"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
    annotations = {
      "resources.teleport.dev/allow-lookup-from-cr" = "*"
    }
  }

  data = {
    "client_secret" = var.github_client_secret
  }

  type = "Opaque"
}

resource "kubectl_manifest" "sso_github" {
  yaml_body = yamlencode(
    {
      apiVersion = "resources.teleport.dev/v3"
      kind       = "TeleportGithubConnector"

      metadata = {
        name      = "github"
        namespace = helm_release.teleport_cluster.namespace
      }

      spec = {
        client_id     = var.github_client_id
        client_secret = "secret://${kubernetes_secret.sso_github.metadata[0].name}/client_secret"
        display       = "GitHub"
        redirect_url  = "https://${local.teleport_cluster_fqdn}:443/v1/webapi/github/callback"
        client_redirect_settings = {
          allowed_https_hostnames = [
            "${local.teleport_cluster_fqdn}:443"
          ]
        }
        teams_to_roles = [
          {
            organization = var.github_org
            team         = "operators"
            roles = [
              # Databases (read-only)
              "${var.resource_prefix}postgresql-ro",
              "${var.resource_prefix}mysql-ro",
              "${var.resource_prefix}mariadb-ro",
              "${var.resource_prefix}mongodb-ro",
              # Kubernetes (read-only)
              "${var.resource_prefix}k8s-ro",
              # AWS (read-only)
              "${var.resource_prefix}aws-console-ro",
              "${var.resource_prefix}aws-bedrock-ro",
              # Apps
              "${var.resource_prefix}grafana",
              "${var.resource_prefix}swagger-ui",
              "${var.resource_prefix}coder",
              # SSH (one node, visitor user)
              "${var.resource_prefix}nodes-ro",
              # Session observation
              "${var.resource_prefix}session-observe",
            ]
          }
        ]
      }
    }
  )
}

output "github_oauth_callback_url" {
  value       = "https://${local.teleport_cluster_fqdn}:443/v1/webapi/github/callback"
  description = "Authorization callback URL for the GitHub OAuth App"
}
