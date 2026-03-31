# Reviewer role — overrides the preset to allow approving any role
resource "kubectl_manifest" "teleport_role_reviewer" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "reviewer"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        review_requests = {
          roles           = ["*"]
          preview_as_roles = ["*"]
        }
      }
    }
  })
}

# Access Request workflow for restricted nodes (tetris, pacman)
# Okta admins (with "reviewer" role) can approve

# Role granted upon approval — allows SSH to nodes with access=restricted
resource "kubectl_manifest" "teleport_role_restricted_access" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}restricted-access"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        logins = ["root"]
        node_labels = {
          access = "restricted"
        }
      }
    }
  })
}

# Role that allows observing any active session (GitHub users)
resource "kubectl_manifest" "teleport_role_session_observe" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}session-observe"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        join_sessions = [{
          name  = "Observe any session"
          roles = ["*"]
          kinds = ["*"]
          modes = ["observer"]
        }]
      }
    }
  })
}

# Role that allows full session moderation (Okta users)
resource "kubectl_manifest" "teleport_role_session_moderate" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}session-moderate"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        join_sessions = [{
          name  = "Moderate any session"
          roles = ["*"]
          kinds = ["*"]
          modes = ["observer", "peer", "moderator"]
        }]
      }
    }
  })
}
