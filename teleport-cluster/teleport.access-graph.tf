# Teleport Access Graph (Identity Security)
#
# Runs as a separate Helm release in its own namespace, backed by a dedicated
# PostgreSQL instance. The Teleport auth service connects to TAG over mTLS
# using a self-signed CA. TAG authenticates Teleport's connection using the
# cluster's Host CA certificate.
#
# Docs: https://goteleport.com/docs/identity-security/access-graph/self-hosted-helm/

# ---------------------------------------------------------------------------- #
# Namespace
# ---------------------------------------------------------------------------- #

resource "kubernetes_namespace_v1" "access_graph" {
  metadata {
    name = "psh-teleport-access-graph"
  }
}

# ---------------------------------------------------------------------------- #
# Host CA — fetched from the running Teleport cluster
# ---------------------------------------------------------------------------- #

data "http" "teleport_host_ca" {
  url = "https://${aws_route53_record.cluster_endpoint.fqdn}/webapi/auth/export?type=tls-host"

  request_timeout_ms = 10000

  retry {
    attempts     = 30
    min_delay_ms = 10000
  }

  depends_on = [
    aws_iam_role_policy_attachment.irsa_attach_dynamodb,
    helm_release.teleport_cluster
  ]
}

# ---------------------------------------------------------------------------- #
# TLS Certificates (self-signed CA + server cert for TAG gRPC listener)
# ---------------------------------------------------------------------------- #

resource "tls_private_key" "tag_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "tag_ca" {
  private_key_pem = tls_private_key.tag_ca.private_key_pem

  subject {
    common_name  = "Access Graph CA"
    organization = "Teleport"
  }

  is_ca_certificate     = true
  validity_period_hours = 87600 # 10 years
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

resource "tls_private_key" "tag_server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "tag_server" {
  private_key_pem = tls_private_key.tag_server.private_key_pem

  subject {
    common_name  = "Access Graph"
    organization = "Teleport"
  }

  dns_names = [
    "teleport-access-graph.psh-teleport-access-graph.svc.cluster.local",
  ]
}

resource "tls_locally_signed_cert" "tag_server" {
  cert_request_pem   = tls_cert_request.tag_server.cert_request_pem
  ca_private_key_pem = tls_private_key.tag_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.tag_ca.cert_pem

  validity_period_hours = 87600 # 10 years
  allowed_uses = [
    "server_auth",
    "client_auth",
    "key_encipherment",
    "digital_signature",
  ]
}

# ---------------------------------------------------------------------------- #
# Kubernetes Secrets (in psh-teleport-access-graph namespace)
# ---------------------------------------------------------------------------- #

resource "kubernetes_secret" "tag_tls" {
  metadata {
    name      = "teleport-access-graph-tls"
    namespace = kubernetes_namespace_v1.access_graph.metadata[0].name
  }

  data = {
    "tls.crt" = tls_locally_signed_cert.tag_server.cert_pem
    "tls.key" = tls_private_key.tag_server.private_key_pem
  }

  type = "kubernetes.io/tls"
}

resource "kubernetes_secret" "tag_postgres" {
  metadata {
    name      = "teleport-access-graph-postgres"
    namespace = kubernetes_namespace_v1.access_graph.metadata[0].name
  }

  data = {
    uri = "postgres://access_graph:${random_password.tag_postgres.result}@tag-postgresql.${kubernetes_namespace_v1.access_graph.metadata[0].name}.svc.cluster.local:5432/access_graph?sslmode=disable"
  }

  type = "Opaque"
}

# ---------------------------------------------------------------------------- #
# PostgreSQL (dedicated Bitnami instance for TAG)
# ---------------------------------------------------------------------------- #

resource "random_password" "tag_postgres" {
  length  = 16
  special = false
}

resource "helm_release" "tag_postgres" {
  name       = "tag-postgresql"
  namespace  = kubernetes_namespace_v1.access_graph.metadata[0].name
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "postgresql"
  version    = "16.7.1"

  wait    = true
  timeout = 600

  values = [<<EOF
    global:
      security:
        allowInsecureImages: true
    image:
      registry: docker.io
      repository: bitnamilegacy/postgresql
      tag: 17.4.0
    auth:
      username: access_graph
      password: ${random_password.tag_postgres.result}
      database: access_graph
    primary:
      persistence:
        enabled: true
        size: 10Gi
      persistentVolumeClaimRetentionPolicy:
        enabled: true
        whenDeleted: Delete
        whenScaled: Retain
  EOF
  ]
}

# ---------------------------------------------------------------------------- #
# ConfigMap for TAG CA cert (in psh-cluster namespace, mounted into auth pods)
# ---------------------------------------------------------------------------- #

resource "kubernetes_config_map" "tag_ca" {
  metadata {
    name      = "teleport-access-graph-ca"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }

  data = {
    "ca.pem" = tls_self_signed_cert.tag_ca.cert_pem
  }
}

# ---------------------------------------------------------------------------- #
# Teleport Access Graph Helm Release
# ---------------------------------------------------------------------------- #

resource "helm_release" "access_graph" {
  name       = "teleport-access-graph"
  namespace  = kubernetes_namespace_v1.access_graph.metadata[0].name
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-access-graph"
  version    = "1.29.6"

  wait    = true
  timeout = 300

  values = [<<EOF
    postgres:
      secretName: ${kubernetes_secret.tag_postgres.metadata[0].name}
    tls:
      existingSecretName: ${kubernetes_secret.tag_tls.metadata[0].name}
    clusterHostCAs:
      - |
        ${indent(8, data.http.teleport_host_ca.response_body)}
  EOF
  ]

  depends_on = [
    helm_release.tag_postgres,
  ]
}
