module "mysql_tls" {
  source             = "./module/db_tls"
  name               = "${var.resource_prefix}mysql-tls"
  namespace          = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  ca_common_name     = "Custom MySQL CA"
  dns_names = [
    "${var.resource_prefix}mysql.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}",
    "${var.resource_prefix}mysql.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}.svc.cluster.local",
  ]
  teleport_db_ca_pem = data.http.teleport_db_ca.response_body
}

resource "kubernetes_config_map" "mysql_custom_init" {
  metadata {
    name      = "${var.resource_prefix}mysql-custom-init"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  data = {
    "setup.sh" = <<-EOF
#!/bin/bash
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<SQL
-- Teleport admin user for auto user provisioning
CREATE USER IF NOT EXISTS 'teleport-admin'@'%' REQUIRE SUBJECT '/CN=teleport-admin';
GRANT SELECT ON mysql.role_edges TO 'teleport-admin'@'%';
GRANT PROCESS, ROLE_ADMIN, CREATE USER ON *.* TO 'teleport-admin'@'%';
CREATE DATABASE IF NOT EXISTS \`teleport\`;
GRANT ALTER ROUTINE, CREATE ROUTINE, EXECUTE ON \`teleport\`.* TO 'teleport-admin'@'%';

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

resource "kubernetes_config_map" "mysql_config" {
  metadata {
    name      = "${var.resource_prefix}mysql-config"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  data = {
    "custom.cnf" = <<-CNF
[mysqld]
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

resource "kubernetes_stateful_set" "mysql" {
  metadata {
    name      = "${var.resource_prefix}mysql"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
    labels    = { app = "${var.resource_prefix}mysql" }
  }
  spec {
    replicas     = 1
    service_name = "${var.resource_prefix}mysql"
    selector {
      match_labels = { app = "${var.resource_prefix}mysql" }
    }
    template {
      metadata {
        labels = { app = "${var.resource_prefix}mysql" }
      }
      spec {
        security_context {
          fs_group = 999
        }
        container {
          name  = "mysql"
          image = "mysql:9.4"
          port {
            container_port = 3306
            name           = "mysql"
          }
          env {
            name  = "MYSQL_ROOT_PASSWORD"
            value = random_password.mysql.result
          }
          env {
            name  = "MYSQL_DATABASE"
            value = "teleport_db"
          }
          env {
            name  = "MYSQL_USER"
            value = "admin"
          }
          env {
            name  = "MYSQL_PASSWORD"
            value = random_password.mysql.result
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
              command = ["mysqladmin", "ping", "-h", "127.0.0.1", "-uroot", "-p${random_password.mysql.result}"]
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
          liveness_probe {
            exec {
              command = ["mysqladmin", "ping", "-h", "127.0.0.1", "-uroot", "-p${random_password.mysql.result}"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }
        volume {
          name = "certs"
          secret {
            secret_name  = "${var.resource_prefix}mysql-tls"
            default_mode = "0640"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.mysql_config.metadata[0].name
          }
        }
        volume {
          name = "init"
          config_map {
            name         = kubernetes_config_map.mysql_custom_init.metadata[0].name
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

resource "kubernetes_service" "mysql" {
  metadata {
    name      = "${var.resource_prefix}mysql"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  spec {
    selector = { app = "${var.resource_prefix}mysql" }
    port {
      port        = 3306
      target_port = 3306
      name        = "mysql"
    }
  }
}

resource "kubectl_manifest" "teleport_role_mysql" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "${var.resource_prefix}mysql"
      namespace = helm_release.teleport_cluster.namespace
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
        db_roles = ["admin", "read_only"]
      }
    }
  })
}

moved {
  from = module.mysql.module.tls
  to   = module.mysql_tls
}

moved {
  from = module.mysql.kubernetes_config_map.init
  to   = kubernetes_config_map.mysql_custom_init
}

moved {
  from = module.mysql.kubectl_manifest.teleport_role
  to   = kubectl_manifest.teleport_role_mysql
}
