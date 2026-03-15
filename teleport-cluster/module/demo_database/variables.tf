variable "db_type" {
  type        = string
  description = "Database type: postgresql, mysql, or mariadb"
}

variable "resource_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace"
}

variable "teleport_cluster_namespace" {
  type        = string
  description = "Namespace where the Teleport cluster helm release lives"
}

variable "ca_common_name" {
  type        = string
  description = "CA common name for TLS certificates"
}

variable "dns_names" {
  type        = list(string)
  description = "DNS names for TLS certificates"
}

variable "teleport_db_ca_pem" {
  type        = string
  description = "Teleport DB CA PEM certificate"
}

variable "init_sql" {
  type        = string
  description = "Full init SQL script content (wrapped in shell script)"
}

variable "chart_values" {
  type        = string
  description = "Helm chart values YAML"
}

variable "tls_secret_name" {
  type        = string
  description = "Override the TLS secret name (defaults to {resource_prefix}{db_type}-tls)"
  default     = null
}

variable "teleport_role_spec" {
  type        = any
  description = "Spec block for the TeleportRoleV7 resource"
}
