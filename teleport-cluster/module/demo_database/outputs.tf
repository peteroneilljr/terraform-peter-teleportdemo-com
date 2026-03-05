output "tls_secret_name" {
  value = module.tls.secret_name
}

output "config_map_name" {
  value = kubernetes_config_map.init.metadata[0].name
}

output "helm_release_name" {
  value = helm_release.db.name
}

output "helm_release_namespace" {
  value = helm_release.db.namespace
}
