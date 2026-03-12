output "secret_name" {
  value = kubernetes_secret.this.metadata[0].name
}

output "ca_cert_pem" {
  value     = "${tls_self_signed_cert.ca.cert_pem}${var.teleport_db_ca_pem}"
  sensitive = true
}
