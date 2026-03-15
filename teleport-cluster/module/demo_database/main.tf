terraform {
  required_providers {
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }
}

module "tls" {
  source             = "../db_tls"
  name               = coalesce(var.tls_secret_name, "${var.resource_prefix}${var.db_type}-tls")
  namespace          = var.namespace
  ca_common_name     = var.ca_common_name
  dns_names          = var.dns_names
  teleport_db_ca_pem = var.teleport_db_ca_pem
}

resource "kubernetes_config_map" "init" {
  metadata {
    name      = "${var.resource_prefix}${var.db_type}-custom-init"
    namespace = var.namespace
  }

  data = {
    "setup.sh" = var.init_sql
  }
}

resource "helm_release" "db" {
  name       = "${var.resource_prefix}${var.db_type == "postgresql" ? "postgres" : var.db_type}"
  namespace  = var.namespace
  repository = "https://charts.bitnami.com/bitnami"
  chart      = var.db_type == "postgresql" ? "postgresql" : var.db_type

  wait = false

  values = [var.chart_values]
}

resource "kubectl_manifest" "teleport_role" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "${var.resource_prefix}${var.db_type}"
      namespace = var.teleport_cluster_namespace
    }
    spec = var.teleport_role_spec
  })
}
