module "mariadb_tls" {
  source         = "./module/db_tls"
  name           = "mariadb-crt"
  namespace      = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  ca_common_name = "Custom MariaDB CA"
  dns_names = [
    "${var.resource_prefix}mariadb.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}",
    "${var.resource_prefix}mariadb.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}.svc.cluster.local",
  ]
  teleport_db_ca_pem = data.http.teleport_db_ca.response_body
}

resource "kubernetes_config_map" "mariadb_custom_init" {
  metadata {
    name      = "${var.resource_prefix}mariadb-custom-init"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  data = {
    "setup.sh" = <<-EOF
#!/bin/bash
mysql -u root -p"$MARIADB_ROOT_PASSWORD" <<SQL
-- Teleport admin user for auto user provisioning
CREATE USER IF NOT EXISTS 'teleport-admin'@'%' REQUIRE SUBJECT '/CN=teleport-admin';
GRANT SELECT ON mysql.roles_mapping TO 'teleport-admin'@'%';
GRANT UPDATE ON mysql.* TO 'teleport-admin'@'%';
GRANT SELECT ON *.* TO 'teleport-admin'@'%';
GRANT PROCESS, CREATE USER ON *.* TO 'teleport-admin'@'%';
CREATE DATABASE IF NOT EXISTS \`teleport\`;
GRANT ALL ON \`teleport\`.* TO 'teleport-admin'@'%' WITH GRANT OPTION;

-- Roles for auto-provisioned users
CREATE ROLE IF NOT EXISTS 'admin';
GRANT ALL PRIVILEGES ON \`teleport_db\`.* TO 'admin';
CREATE ROLE IF NOT EXISTS 'read_only';
GRANT SELECT ON \`teleport_db\`.* TO 'read_only';

-- Grant teleport-admin the ability to assign roles
GRANT 'admin' TO 'teleport-admin'@'%' WITH ADMIN OPTION;
GRANT 'read_only' TO 'teleport-admin'@'%' WITH ADMIN OPTION;

-- Legacy static user
CREATE USER IF NOT EXISTS 'developer'@'%' REQUIRE SUBJECT '/CN=developer';
GRANT ALL PRIVILEGES ON *.* TO 'developer'@'%';

-- Seed data
USE teleport_db;

${local.seed_movies_mysql_sql}
SQL
    EOF
  }
}

resource "kubernetes_config_map" "mariadb_config" {
  metadata {
    name      = "${var.resource_prefix}mariadb-config"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  data = {
    "custom.cnf" = <<-CNF
[mariadbd]
require_secure_transport = ON
ssl_ca   = /certs/ca.crt
ssl_cert = /certs/tls.crt
ssl_key  = /certs/tls.key
# Memory optimizations for demo cluster
innodb_buffer_pool_size = 32M
innodb_log_buffer_size = 4M
max_connections = 20
table_open_cache = 200
    CNF
  }
}

resource "kubernetes_stateful_set" "mariadb" {
  metadata {
    name      = "${var.resource_prefix}mariadb"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
    labels    = { app = "${var.resource_prefix}mariadb" }
  }
  spec {
    replicas     = 1
    service_name = "${var.resource_prefix}mariadb"
    selector {
      match_labels = { app = "${var.resource_prefix}mariadb" }
    }
    template {
      metadata {
        labels = { app = "${var.resource_prefix}mariadb" }
      }
      spec {
        security_context {
          fs_group = 999
        }
        container {
          name  = "mariadb"
          image = "mariadb:11"
          port {
            container_port = 3306
            name           = "mariadb"
          }
          env {
            name  = "MARIADB_ROOT_PASSWORD"
            value = random_password.mariadb_root.result
          }
          env {
            name  = "MARIADB_DATABASE"
            value = "teleport_db"
          }
          env {
            name  = "MARIADB_USER"
            value = "admin"
          }
          env {
            name  = "MARIADB_PASSWORD"
            value = random_password.mariadb.result
          }
          volume_mount {
            name       = "certs"
            mount_path = "/certs"
            read_only  = true
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/mysql/conf.d/custom.cnf"
            sub_path   = "custom.cnf"
          }
          volume_mount {
            name       = "init"
            mount_path = "/docker-entrypoint-initdb.d"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/mysql"
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              memory = "512Mi"
            }
          }
          readiness_probe {
            exec {
              command = ["mariadb-admin", "ping", "-h", "127.0.0.1", "-uroot", "-p${random_password.mariadb_root.result}"]
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
          liveness_probe {
            exec {
              command = ["mariadb-admin", "ping", "-h", "127.0.0.1", "-uroot", "-p${random_password.mariadb_root.result}"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }
        volume {
          name = "certs"
          secret {
            secret_name  = "mariadb-crt"
            default_mode = "0640"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.mariadb_config.metadata[0].name
          }
        }
        volume {
          name = "init"
          config_map {
            name         = kubernetes_config_map.mariadb_custom_init.metadata[0].name
            default_mode = "0755"
          }
        }
        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "mariadb" {
  metadata {
    name      = "${var.resource_prefix}mariadb"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  spec {
    selector = { app = "${var.resource_prefix}mariadb" }
    port {
      port        = 3306
      target_port = 3306
      name        = "mariadb"
    }
  }
}

resource "kubectl_manifest" "teleport_role_mariadb" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "${var.resource_prefix}mariadb"
      namespace = helm_release.teleport_cluster.namespace
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
        db_roles = ["admin", "read_only"]
      }
    }
  })
}

moved {
  from = module.mariadb.module.tls
  to   = module.mariadb_tls
}

moved {
  from = module.mariadb.kubernetes_config_map.init
  to   = kubernetes_config_map.mariadb_custom_init
}

moved {
  from = module.mariadb.kubectl_manifest.teleport_role
  to   = kubectl_manifest.teleport_role_mariadb
}
