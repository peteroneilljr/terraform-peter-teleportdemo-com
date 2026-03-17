output "teleport_cluster_fqdn" {
  value       = local.teleport_cluster_fqdn
  description = "FQDN of the teleport cluster"
  sensitive   = false
}

output "teleport_db_backend_name" {
  value = aws_dynamodb_table.teleport_backend.name
}
output "teleport_db_events_name" {
  value = aws_dynamodb_table.teleport_events.name
}
output "teleport_s3_sessions_name" {
  value = aws_s3_bucket.teleport_sessions.bucket
}
output "bedrock_inference_profile_arn" {
  value       = "arn:aws:bedrock:us-west-2:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-sonnet-4-6"
  description = "ARN of the Bedrock cross-region inference profile for Teleport session summaries"
}
