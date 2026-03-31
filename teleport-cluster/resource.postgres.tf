module "postgres" {
  source = "./module/demo_database"

  db_type                    = "postgresql"
  resource_prefix            = var.resource_prefix
  namespace                  = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  teleport_cluster_namespace = helm_release.teleport_cluster.namespace
  ca_common_name             = "Custom PostgreSQL CA"
  dns_names = [
    "${var.resource_prefix}postgres-postgresql.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}",
    "${var.resource_prefix}postgres-postgresql.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}.svc.cluster.local",
  ]
  teleport_db_ca_pem = data.http.teleport_db_ca.response_body

  init_sql = <<-EOF
    #!/bin/bash
    set -e
    PGPASSWORD="$POSTGRESQL_POSTGRES_PASSWORD" psql -U postgres -d teleport_db -v ON_ERROR_STOP=1 <<SQL
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
    PGPASSWORD="$POSTGRESQL_POSTGRES_PASSWORD" psql -U postgres -v ON_ERROR_STOP=1 <<SQL
    SELECT 'CREATE DATABASE coder' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'coder')\gexec
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
    PGPASSWORD="$POSTGRESQL_POSTGRES_PASSWORD" psql -U postgres -d coder -v ON_ERROR_STOP=1 <<SQL
    ALTER SCHEMA public OWNER TO coder;
    SQL
  EOF

  chart_values = <<-EOF
    image:
      registry: docker.io
      repository: bitnamilegacy/postgresql
      tag: 17.4.0
    volumePermissions:
      image:
        registry: docker.io
        repository: bitnamilegacy/os-shell
        tag: latest
    tls:
      enabled: true
      preferServerCiphers: true
      certificatesSecret: ${var.resource_prefix}postgresql-tls
      certFilename: tls.crt
      certKeyFilename: tls.key
      certCAFilename: ca.crt

    auth:
      username: developer
      password: ${random_password.postgres.result}
      postgresPassword: ${random_password.postgres_superuser.result}
      database: teleport_db

    primary:
      resources:
        requests:
          cpu: 25m
          memory: 128Mi
      extraVolumes:
        - name: custom-init
          configMap:
            name: ${var.resource_prefix}postgresql-custom-init
            defaultMode: 0755
      extraVolumeMounts:
        - name: custom-init
          mountPath: /docker-entrypoint-initdb.d
      pgHbaConfiguration: |-
        local all all trust
        hostssl all teleport-admin all cert
        hostssl all developer all md5
        hostssl coder coder all md5
        hostssl all all all cert
      persistence:
          enabled: false
      shmVolume:
        enabled: true
      extraFlags:
        - "-c ssl=on"
        - "-c ssl_ca_file=/opt/bitnami/postgresql/certs/ca.crt"
        - "-c ssl_cert_file=/opt/bitnami/postgresql/certs/tls.crt"
        - "-c ssl_key_file=/opt/bitnami/postgresql/certs/tls.key"
      persistentVolumeClaimRetentionPolicy:
        enabled: true
        whenDeleted: Delete
        whenScaled: Retain
  EOF

  teleport_role_spec = {
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
}

moved {
  from = module.postgres_tls
  to   = module.postgres.module.tls
}

moved {
  from = kubernetes_config_map.postgres_custom_init
  to   = module.postgres.kubernetes_config_map.init
}

moved {
  from = helm_release.postgresql
  to   = module.postgres.helm_release.db
}

moved {
  from = kubectl_manifest.teleport_role_postgresql
  to   = module.postgres.kubectl_manifest.teleport_role
}
