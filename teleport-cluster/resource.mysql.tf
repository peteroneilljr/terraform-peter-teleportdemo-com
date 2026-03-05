module "mysql" {
  source = "./module/demo_database"

  db_type                    = "mysql"
  resource_prefix            = var.resource_prefix
  namespace                  = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  teleport_cluster_namespace = helm_release.teleport_cluster.namespace
  ca_common_name             = "Custom MySQL CA"
  dns_names = [
    "${var.resource_prefix}mysql.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}",
    "${var.resource_prefix}mysql.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}.svc.cluster.local",
  ]
  teleport_db_ca_pem = data.http.teleport_db_ca.response_body

  init_sql = <<-EOF
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

  chart_values = <<-EOF
    image:
      registry: docker.io
      repository: bitnamilegacy/mysql
      tag: 9.4.0-debian-12-r1
    primary:
      extraVolumes:
        - name: custom-init
          configMap:
            name: ${var.resource_prefix}mysql-custom-init
            defaultMode: 0755
      extraVolumeMounts:
        - name: custom-init
          mountPath: /docker-entrypoint-initdb.d
      persistence:
        enabled: false
      extraFlags: "--require-secure-transport=ON --ssl-ca=/opt/bitnami/mysql/certs/ca.crt --ssl-cert=/opt/bitnami/mysql/certs/tls.crt --ssl-key=/opt/bitnami/mysql/certs/tls.key"
    auth:
      database: teleport_db
      username: admin
      password: ${random_password.mysql.result}
    tls:
      enabled: true
      existingSecret: ${var.resource_prefix}mysql-tls
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
        db = "mysql"
      }
      db_names = ["teleport_db", "*"]
      db_roles = ["admin", "read_only"]
    }
  }
}

moved {
  from = module.mysql_tls
  to   = module.mysql.module.tls
}

moved {
  from = kubernetes_config_map.mysql_custom_init
  to   = module.mysql.kubernetes_config_map.init
}

moved {
  from = helm_release.mysql
  to   = module.mysql.helm_release.db
}

moved {
  from = kubectl_manifest.teleport_role_mysql
  to   = module.mysql.kubectl_manifest.teleport_role
}
