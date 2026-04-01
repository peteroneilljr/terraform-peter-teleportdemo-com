resource "kubectl_manifest" "teleport_db_postgres" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportDatabaseV3"
    metadata = {
      name      = "postgres"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s", db = "postgres" }
    }
    spec = {
      protocol = "postgres"
      uri      = "${kubernetes_service.postgres.metadata[0].name}.${kubernetes_service.postgres.metadata[0].namespace}.svc.cluster.local:5432"
      admin_user = {
        name = "teleport-admin"
      }
      tls = {
        ca_cert = module.postgres_tls.ca_cert_pem
      }
    }
  })
}

resource "kubectl_manifest" "teleport_db_mysql" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportDatabaseV3"
    metadata = {
      name      = "mysql"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s", db = "mysql" }
    }
    spec = {
      protocol = "mysql"
      uri      = "${kubernetes_service.mysql.metadata[0].name}.${kubernetes_service.mysql.metadata[0].namespace}.svc.cluster.local:3306"
      admin_user = {
        name = "teleport-admin"
      }
      tls = {
        ca_cert = module.mysql_tls.ca_cert_pem
      }
    }
  })
}

resource "kubectl_manifest" "teleport_db_mariadb" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportDatabaseV3"
    metadata = {
      name      = "mariadb"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s", db = "mariadb" }
    }
    spec = {
      protocol = "mysql"
      uri      = "${kubernetes_service.mariadb.metadata[0].name}.${kubernetes_service.mariadb.metadata[0].namespace}.svc.cluster.local:3306"
      admin_user = {
        name = "teleport-admin"
      }
      tls = {
        ca_cert = module.mariadb_tls.ca_cert_pem
      }
    }
  })
}

resource "kubectl_manifest" "teleport_db_mongodb_atlas" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportDatabaseV3"
    metadata = {
      name      = "mongodb-atlas"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "atlas", db = "mongodb" }
    }
    spec = {
      protocol = "mongodb"
      uri      = mongodbatlas_advanced_cluster.mongodb.connection_strings.standard_srv
    }
  })
}
