output "mcp_client_join_token" {
  description = "Join token for the local mcp-client tbot (used in ~/.tbot-<cluster>/tbot.yaml). Sensitive — store securely."
  value       = random_password.mcp_client_token.result
  sensitive   = true
}

output "namespace" {
  description = "Kubernetes namespace where the MCP server workload is deployed."
  value       = kubernetes_namespace_v1.teleport_mcp.metadata[0].name
}

output "service_name" {
  description = "Kubernetes Service name for the MCP server (ClusterIP on port 8011)."
  value       = kubernetes_service_v1.teleport_mcp.metadata[0].name
}

output "service_fqdn" {
  description = "In-cluster DNS name for the MCP server service."
  value       = "${kubernetes_service_v1.teleport_mcp.metadata[0].name}.${kubernetes_namespace_v1.teleport_mcp.metadata[0].name}.svc.cluster.local"
}
