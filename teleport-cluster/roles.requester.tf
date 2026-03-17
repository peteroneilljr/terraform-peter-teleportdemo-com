# Requester role for GitHub SSO users — allows requesting elevated access
# Okta admins (with "reviewer" role) can approve these requests

resource "kubectl_manifest" "teleport_role_requester" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}requester"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        request = {
          roles = [
            "${var.resource_prefix}postgresql",
            "${var.resource_prefix}mysql",
            "${var.resource_prefix}mariadb",
            "${var.resource_prefix}mongodb",
            "${var.resource_prefix}elasticsearch",
            "${var.resource_prefix}k8s",
            "${var.resource_prefix}aws-console",
            "${var.resource_prefix}restricted-access",
          ]
          search_as_roles = [
            "${var.resource_prefix}postgresql",
            "${var.resource_prefix}mysql",
            "${var.resource_prefix}mariadb",
            "${var.resource_prefix}mongodb",
            "${var.resource_prefix}elasticsearch",
            "${var.resource_prefix}k8s",
            "${var.resource_prefix}aws-console",
            "${var.resource_prefix}restricted-access",
          ]
        }
      }
    }
  })
}
