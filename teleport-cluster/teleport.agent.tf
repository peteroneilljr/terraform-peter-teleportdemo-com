resource "random_string" "teleport_agent" {
  length  = 32
  special = false
  upper   = false
  lower   = true
}

resource "kubectl_manifest" "teleport_agent" {
  yaml_body = yamlencode(
    {
      apiVersion = "resources.teleport.dev/v2"
      kind       = "TeleportProvisionToken"

      metadata = {
        name      = random_string.teleport_agent.result
        namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
      }

      spec = {
        roles       = ["App", "Db"]
        join_method = "token"

      }
    }
  )

  depends_on = [
    helm_release.teleport_cluster
  ]
}

locals {
  teleport_agent_name = "${var.resource_prefix}teleport-agent"
}


resource "helm_release" "teleport_agent" {
  name       = local.teleport_agent_name
  namespace  = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-kube-agent"
  version    = var.teleport_version

  set = [
    {
      name  = "authToken"
      value = random_string.teleport_agent.result
    }
  ]

  wait = false

  values = [<<EOF
roles: app,db
proxyAddr: ${local.teleport_cluster_fqdn}:443
enterprise: true
annotations:
  serviceAccount:
    "eks.amazonaws.com/role-arn": "${aws_iam_role.irsa_aws_console.arn}"
highAvailability:
    replicaCount: 2
    podDisruptionBudget:
        enabled: true
        minAvailable: 1 
extraVolumes:
- name: postgres-ca
  secret:
    secretName: ${module.postgres.tls_secret_name}
- name: mysql-ca
  secret:
    secretName: ${module.mysql.tls_secret_name}
- name: mariadb-ca
  secret:
    secretName: ${module.mariadb.tls_secret_name}
extraVolumeMounts:
- name: postgres-ca
  mountPath: /var/lib/postgresql/tls
- name: mysql-ca
  mountPath: /var/lib/mysql/tls
- name: mariadb-ca
  mountPath: /var/lib/mariadb/tls
apps:
  - name: grafana
    public_addr: "grafana.${local.teleport_cluster_fqdn}"
    uri: http://${helm_release.grafana.name}.${helm_release.grafana.namespace}.svc.cluster.local
    labels:
      env: dev
      host: k8s
  - name: argocd
    uri: https://argocd-server.argocd.svc.cluster.local
    insecure_skip_verify: true
    labels:
      env: dev
      host: k8s
      app: argocd
  - name: awsconsole
    uri: "https://console.aws.amazon.com/"
    labels:
      env: dev
      host: k8s
      app: aws
  - name: awsconsole-bedrock
    uri: "https://console.aws.amazon.com/bedrock"
    labels:
      app: bedrock
  - name: coder
    public_addr: "coder.${local.teleport_cluster_fqdn}"
    uri: http://coder.coder.svc.cluster.local
    labels:
      env: dev
      host: k8s
      app: coder
  - name: swagger-ui
    public_addr: "swagger-ui.${local.teleport_cluster_fqdn}"
    uri: http://psh-swagger-ui.${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}.svc.cluster.local:8080
    labels:
      env: dev
      host: k8s
      app: swagger-ui

databases:
  - name: postgres
    uri: ${module.postgres.helm_release_name}-postgresql.${module.postgres.helm_release_namespace}.svc.cluster.local:5432
    protocol: postgres
    admin_user:
      name: teleport-admin
    static_labels:
      env: dev
      host: k8s
      db: postgres
    tls:
      ca_cert_file: /var/lib/postgresql/tls/ca.crt
  - name: mysql
    uri: ${module.mysql.helm_release_name}.${module.mysql.helm_release_namespace}.svc.cluster.local:3306
    protocol: mysql
    admin_user:
      name: teleport-admin
    static_labels:
      env: dev
      host: k8s
      db: mysql
    tls:
      ca_cert_file: /var/lib/mysql/tls/ca.crt
  - name: mariadb
    uri: ${module.mariadb.helm_release_name}.${module.mariadb.helm_release_namespace}.svc.cluster.local:3306
    protocol: mysql
    admin_user:
      name: teleport-admin
    static_labels:
      env: dev
      host: k8s
      db: mariadb
    tls:
      ca_cert_file: /var/lib/mariadb/tls/ca.crt
  - name: mongodb-atlas
    uri: "${mongodbatlas_advanced_cluster.mongodb.connection_strings.standard_srv}"
    protocol: mongodb
    static_labels:
      env: dev
      host: atlas
      db: mongodb
EOF
  ]
}
