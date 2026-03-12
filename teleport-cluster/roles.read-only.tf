# Read-only Teleport roles for GitHub SSO users

# ---------------------------------------------------------------------------- #
# Database Read-Only Roles
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "teleport_role_postgresql_ro" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}postgresql-ro"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      options = {
        create_db_user_mode = "keep"
      }
      allow = {
        db_labels = {
          db = "postgres"
        }
        db_names = ["teleport_db", "*"]
        db_roles = ["read_only"]
      }
    }
  })
}

resource "kubectl_manifest" "teleport_role_mysql_ro" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}mysql-ro"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      options = {
        create_db_user_mode = "keep"
      }
      allow = {
        db_labels = {
          db = "mysql"
        }
        db_names = ["teleport_db", "*"]
        db_roles = ["read_only"]
      }
    }
  })
}

resource "kubectl_manifest" "teleport_role_mariadb_ro" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}mariadb-ro"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      options = {
        create_db_user_mode = "keep"
      }
      allow = {
        db_labels = {
          db = "mariadb"
        }
        db_names = ["teleport_db", "*"]
        db_roles = ["read_only"]
      }
    }
  })
}

# ---------------------------------------------------------------------------- #
# MongoDB Read-Only Role
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "teleport_role_mongodb_ro" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}mongodb-ro"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        db_labels = {
          db = "mongodb"
        }
        db_users = ["teleport-readonly"]
        db_names = ["admin", "*"]
      }
    }
  })
}

# ---------------------------------------------------------------------------- #
# Kubernetes Read-Only Role
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "teleport_role_k8s_ro" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}k8s-ro"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        kubernetes_groups = ["read-only"]
        kubernetes_labels = {
          "*" = "*"
        }
        kubernetes_resources = [
          {
            kind      = "*"
            name      = "*"
            namespace = "*"
            verbs     = ["get", "list", "watch"]
          }
        ]
      }
    }
  })
}

# ---------------------------------------------------------------------------- #
# AWS Console Read-Only Role
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "teleport_role_aws_console_ro" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}aws-console-ro"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        app_labels = {
          app = "aws"
        }
        aws_role_arns = [
          aws_iam_role.irsa_aws_console_ro.arn,
        ]
      }
    }
  })
}

# ---------------------------------------------------------------------------- #
# SSH Node Read-Only Role
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "teleport_role_nodes_ro" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}nodes-ro"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      options = {
        max_session_ttl                = "4h"
        create_host_user_mode          = "keep"
        create_host_user_default_shell = "/bin/bash"
      }
      allow = {
        logins = ["visitor"]
        node_labels = {
          hostname = "ubuntu2404"
        }
        host_groups = []
      }
    }
  })
}
