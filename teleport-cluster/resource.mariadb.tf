module "mariadb" {
  source = "./module/demo_database"

  db_type                    = "mariadb"
  resource_prefix            = var.resource_prefix
  tls_secret_name            = "mariadb-crt"
  namespace                  = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  teleport_cluster_namespace = helm_release.teleport_cluster.namespace
  ca_common_name             = "Custom MariaDB CA"
  dns_names = [
    "${var.resource_prefix}mariadb.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}",
    "${var.resource_prefix}mariadb.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}.svc.cluster.local",
  ]
  teleport_db_ca_pem = data.http.teleport_db_ca.response_body

  init_sql = <<-EOF
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

  chart_values = <<-EOF
    primary:
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
      extraVolumes:
        - name: custom-init
          configMap:
            name: ${var.resource_prefix}mariadb-custom-init
            defaultMode: 0755
      extraVolumeMounts:
        - name: custom-init
          mountPath: /docker-entrypoint-initdb.d
      persistence:
        enabled: false
      extraFlags: "--require-secure-transport=ON --ssl-ca=/opt/bitnami/mariadb/certs/ca.crt --ssl-cert=/opt/bitnami/mariadb/certs/tls.crt --ssl-key=/opt/bitnami/mariadb/certs/tls.key"
    auth:
      rootPassword: ${random_password.mariadb_root.result}
      database: teleport_db
      username: admin
      password: ${random_password.mariadb.result}
    tls:
      enabled: true
      existingSecret: mariadb-crt
      certFilename: tls.crt
      certKeyFilename: tls.key
      certCAFilename: ca.crt
  EOF

  teleport_role_spec = {
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
}

moved {
  from = module.mariadb_tls
  to   = module.mariadb.module.tls
}

moved {
  from = kubernetes_config_map.mariadb_custom_init
  to   = module.mariadb.kubernetes_config_map.init
}

moved {
  from = helm_release.mariadb
  to   = module.mariadb.helm_release.db
}

moved {
  from = kubectl_manifest.teleport_role_mariadb
  to   = module.mariadb.kubectl_manifest.teleport_role
}
