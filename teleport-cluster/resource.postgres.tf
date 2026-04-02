module "postgres_tls" {
  source             = "./module/db_tls"
  name               = "${var.resource_prefix}postgresql-tls"
  namespace          = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  ca_common_name     = "Custom PostgreSQL CA"
  dns_names = [
    "${var.resource_prefix}postgres.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}",
    "${var.resource_prefix}postgres.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}.svc.cluster.local",
  ]
  teleport_db_ca_pem = data.http.teleport_db_ca.response_body
}

resource "kubernetes_config_map" "postgres_custom_init" {
  metadata {
    name      = "${var.resource_prefix}postgresql-custom-init"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  data = {
    "setup.sh" = <<-EOF
#!/bin/bash
set -e
PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d teleport_db -v ON_ERROR_STOP=1 <<SQL
CREATE USER "teleport-admin" LOGIN SUPERUSER;
CREATE ROLE "admin" NOLOGIN;
GRANT "admin" TO "teleport-admin" WITH ADMIN OPTION;
GRANT ALL PRIVILEGES ON DATABASE teleport_db TO "admin";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "admin";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "admin";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO "admin";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO "admin";
CREATE ROLE "read_only" NOLOGIN;
GRANT "read_only" TO "teleport-admin" WITH ADMIN OPTION;
GRANT CONNECT ON DATABASE teleport_db TO "read_only";
GRANT USAGE ON SCHEMA public TO "read_only";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "read_only";
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO "read_only";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "read_only";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO "read_only";

${local.seed_movies_postgres_sql}
SQL

# Create Coder database and user
PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d teleport_db -c "SELECT 1 FROM pg_database WHERE datname = 'coder'" | grep -q 1 || \
  PGPASSWORD="$POSTGRES_PASSWORD" createdb -U "$POSTGRES_USER" coder
PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d teleport_db -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'coder') THEN
    CREATE USER coder WITH PASSWORD '${random_password.coder_db.result}';
  END IF;
END
\$\$;
GRANT ALL PRIVILEGES ON DATABASE coder TO coder;
SQL

# Grant coder user ownership of public schema in coder database
PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d coder -v ON_ERROR_STOP=1 <<SQL
ALTER SCHEMA public OWNER TO coder;
SQL
    EOF
  }
}

resource "kubernetes_config_map" "postgres_config" {
  metadata {
    name      = "${var.resource_prefix}postgresql-config"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  data = {
    "pg_hba.conf" = <<-CONF
local all all trust
hostssl all teleport-admin all cert
hostssl all developer all md5
hostssl coder coder all md5
hostssl all all all cert
    CONF
  }
}

resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = "${var.resource_prefix}postgres"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
    labels    = { app = "${var.resource_prefix}postgres" }
  }
  spec {
    replicas     = 1
    service_name = "${var.resource_prefix}postgres"
    selector {
      match_labels = { app = "${var.resource_prefix}postgres" }
    }
    template {
      metadata {
        labels = { app = "${var.resource_prefix}postgres" }
      }
      spec {
        security_context {
          fs_group    = 999
          run_as_user = 999
        }
        container {
          name  = "postgres"
          image = "postgres:17"
          args = [
            "-c", "ssl=on",
            "-c", "ssl_cert_file=/certs/tls.crt",
            "-c", "ssl_key_file=/certs/tls.key",
            "-c", "ssl_ca_file=/certs/ca.crt",
            "-c", "shared_buffers=32MB",
            "-c", "work_mem=2MB",
            "-c", "max_connections=20",
            "-c", "hba_file=/etc/postgresql/pg_hba.conf",
          ]
          port {
            container_port = 5432
            name           = "postgres"
          }
          env {
            name  = "POSTGRES_USER"
            value = "developer"
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = random_password.postgres.result
          }
          env {
            name  = "POSTGRES_DB"
            value = "teleport_db"
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          volume_mount {
            name       = "certs"
            mount_path = "/certs"
            read_only  = true
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/postgresql/pg_hba.conf"
            sub_path   = "pg_hba.conf"
          }
          volume_mount {
            name       = "init"
            mount_path = "/docker-entrypoint-initdb.d"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
          resources {
            requests = {
              cpu    = "25m"
              memory = "128Mi"
            }
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "developer", "-d", "teleport_db"]
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "developer", "-d", "teleport_db"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }
        volume {
          name = "certs"
          secret {
            # PostgreSQL requires the key file to be 0600
            secret_name  = module.postgres_tls.secret_name
            default_mode = "0600"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.postgres_config.metadata[0].name
          }
        }
        volume {
          name = "init"
          config_map {
            name         = kubernetes_config_map.postgres_custom_init.metadata[0].name
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

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "${var.resource_prefix}postgres"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  spec {
    selector = { app = "${var.resource_prefix}postgres" }
    port {
      port        = 5432
      target_port = 5432
      name        = "postgres"
    }
  }
}

resource "kubectl_manifest" "teleport_role_postgresql" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "${var.resource_prefix}postgresql"
      namespace = helm_release.teleport_cluster.namespace
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
        db_roles = ["admin", "read_only"]
      }
    }
  })
}

moved {
  from = module.postgres.module.tls
  to   = module.postgres_tls
}

moved {
  from = module.postgres.kubernetes_config_map.init
  to   = kubernetes_config_map.postgres_custom_init
}

moved {
  from = module.postgres.kubectl_manifest.teleport_role
  to   = kubectl_manifest.teleport_role_postgresql
}
