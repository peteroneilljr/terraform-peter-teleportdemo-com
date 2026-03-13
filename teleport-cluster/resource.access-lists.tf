# ---------------------------------------------------------------------------- #
# Access List Admin Role
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "teleport_role_access_list_admin" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}access-list-admin"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        rules = [
          {
            resources = ["access_list"]
            verbs     = ["list", "read", "create", "update", "delete"]
          }
        ]
      }
    }
  })
}

# ---------------------------------------------------------------------------- #
# Access Lists
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "access_list_database_admins" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAccessList"
    metadata = {
      name      = "${var.resource_prefix}database-admins"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      title       = "Database Administrators"
      description = "Grants standing access to all database roles. Reviewed quarterly."
      owners = [
        { name = "peter.oneill@goteleport.com" }
      ]
      ownership_requires = {
        roles = ["editor"]
      }
      membership_requires = {
        roles = ["access"]
      }
      grants = {
        roles = [
          "${var.resource_prefix}postgresql",
          "${var.resource_prefix}mysql",
          "${var.resource_prefix}mariadb",
          "${var.resource_prefix}mongodb",
        ]
      }
      audit = {
        recurrence = {
          frequency    = "3"
          day_of_month = "1"
        }
        notifications = {
          start = "720h"
        }
      }
    }
    status = {
      members = [
        {
          name            = "peter.oneill@goteleport.com"
          joined          = "2026-03-12T00:00:00Z"
          expires         = "0001-01-01T00:00:00Z"
          membership_kind = "MEMBERSHIP_KIND_USER"
        }
      ]
    }
  })
}

resource "kubectl_manifest" "access_list_infra_operators" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAccessList"
    metadata = {
      name      = "${var.resource_prefix}infra-operators"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      title       = "Infrastructure Operators"
      description = "Grants standing access to Kubernetes and AWS console roles. Reviewed monthly."
      owners = [
        { name = "peter.oneill@goteleport.com" }
      ]
      ownership_requires = {
        roles = ["editor"]
      }
      membership_requires = {
        roles = ["access"]
      }
      grants = {
        roles = [
          "${var.resource_prefix}k8s",
          "${var.resource_prefix}aws-console",
        ]
      }
      audit = {
        recurrence = {
          frequency    = "1"
          day_of_month = "1"
        }
        notifications = {
          start = "720h"
        }
      }
    }
    status = {
      members = [
        {
          name            = "peter.oneill@goteleport.com"
          joined          = "2026-03-12T00:00:00Z"
          expires         = "0001-01-01T00:00:00Z"
          membership_kind = "MEMBERSHIP_KIND_USER"
        }
      ]
    }
  })
}

resource "kubectl_manifest" "access_list_restricted_node_access" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAccessList"
    metadata = {
      name      = "${var.resource_prefix}restricted-node-access"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      title       = "Restricted Node Access"
      description = "Grants standing restricted node access. Reviewed monthly."
      owners = [
        { name = "peter.oneill@goteleport.com" }
      ]
      ownership_requires = {
        roles = ["editor"]
      }
      membership_requires = {
        roles = ["${var.resource_prefix}restricted-requester"]
      }
      grants = {
        roles = [
          "${var.resource_prefix}restricted-access",
        ]
      }
      audit = {
        recurrence = {
          frequency    = "1"
          day_of_month = "1"
        }
        notifications = {
          start = "720h"
        }
      }
    }
  })
}
