# Access Request workflow for restricted nodes (tetris, pacman)
# restricted-user can request access; Okta admins (with "reviewer" role) can approve

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

# Role assigned to restricted-user — allows discovering and requesting access
resource "kubectl_manifest" "teleport_role_restricted_requester" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}restricted-requester"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        request = {
          roles           = ["${var.resource_prefix}restricted-access"]
          search_as_roles = ["${var.resource_prefix}restricted-access"]
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

# Local user who can only request access to restricted nodes
resource "kubectl_manifest" "teleport_user_restricted" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportUser"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "restricted-user"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles = ["${var.resource_prefix}restricted-requester"]
    }
  })
}
