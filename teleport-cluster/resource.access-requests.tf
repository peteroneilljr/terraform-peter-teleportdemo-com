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

# Role that allows joining any active SSH session as observer or peer
resource "kubectl_manifest" "teleport_role_session_join" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}session-join"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        join_sessions = [{
          name  = "Join any SSH session"
          roles = ["*"]
          kinds = ["ssh"]
          modes = ["observer", "peer"]
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
