variable "teleport_cluster_fqdn" {
  description = "Fully qualified domain name of the Teleport proxy (e.g. teleport.example.com). Used by both tbot (server-side) and the MCP server container to reach the Teleport auth server."
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to deploy. Must match the version running in your cluster. Used for the tbot sidecar image and the tctl binary download."
  type        = string
  default     = "18.7.0"
}

variable "namespace" {
  description = "Kubernetes namespace to create for the MCP server workload."
  type        = string
  default     = "teleport-mcp"
}

variable "teleport_operator_namespace" {
  description = "Kubernetes namespace where the Teleport operator watches for CRDs (i.e. the namespace where Teleport itself is installed via Helm). TeleportRoleV7, TeleportBotV1, TeleportProvisionToken, and TeleportAppV3 manifests are placed here."
  type        = string
  default     = "teleport"
}

variable "app_labels" {
  description = "Labels to attach to the TeleportAppV3 resource. Useful for scoping the mcp-client role to specific environments."
  type        = map(string)
  default = {
    env  = "prod"
    host = "k8s"
  }
}
