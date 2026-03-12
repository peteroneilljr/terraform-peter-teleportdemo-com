# ---------------------------------------------------------------------------- #
# MongoDB Atlas Cluster (M0 free tier)
# ---------------------------------------------------------------------------- #
resource "mongodbatlas_advanced_cluster" "mongodb" {
  project_id   = var.mongodbatlas_project_id
  name         = "${var.resource_prefix}mongodb"
  cluster_type = "REPLICASET"

  replication_specs = [
    {
      region_configs = [
        {
          electable_specs = {
            instance_size = "M0"
          }
          provider_name         = "TENANT"
          backing_provider_name = "AWS"
          region_name           = "US_WEST_2"
          priority              = 7
        }
      ]
    }
  ]
}

# ---------------------------------------------------------------------------- #
# IP Access List (allow all for dev)
# ---------------------------------------------------------------------------- #
resource "mongodbatlas_project_ip_access_list" "eks" {
  project_id = var.mongodbatlas_project_id
  cidr_block = "0.0.0.0/0"
  comment    = "Dev - allow all"
}

# ---------------------------------------------------------------------------- #
# Self-managed X.509 — upload Teleport DB CA to Atlas
# ---------------------------------------------------------------------------- #
resource "mongodbatlas_x509_authentication_database_user" "teleport" {
  project_id        = var.mongodbatlas_project_id
  customer_x509_cas = data.http.teleport_db_ca.response_body
}

# ---------------------------------------------------------------------------- #
# Atlas Database Users (X.509 cert auth via Teleport)
# ---------------------------------------------------------------------------- #
resource "mongodbatlas_database_user" "admin" {
  username           = "CN=teleport-admin"
  project_id         = var.mongodbatlas_project_id
  auth_database_name = "$external"
  x509_type          = "CUSTOMER"

  roles {
    role_name     = "readWriteAnyDatabase"
    database_name = "admin"
  }

  scopes {
    name = mongodbatlas_advanced_cluster.mongodb.name
    type = "CLUSTER"
  }

  depends_on = [mongodbatlas_x509_authentication_database_user.teleport]
}

resource "mongodbatlas_database_user" "readonly" {
  username           = "CN=teleport-readonly"
  project_id         = var.mongodbatlas_project_id
  auth_database_name = "$external"
  x509_type          = "CUSTOMER"

  roles {
    role_name     = "readAnyDatabase"
    database_name = "admin"
  }

  scopes {
    name = mongodbatlas_advanced_cluster.mongodb.name
    type = "CLUSTER"
  }

  depends_on = [mongodbatlas_x509_authentication_database_user.teleport]
}

# ---------------------------------------------------------------------------- #
# Teleport Role
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "teleport_role_mongodb" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}mongodb"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        db_labels = {
          db = "mongodb"
        }
        db_users = ["teleport-admin", "teleport-readonly"]
        db_names = ["admin", "*"]
      }
    }
  })
}
