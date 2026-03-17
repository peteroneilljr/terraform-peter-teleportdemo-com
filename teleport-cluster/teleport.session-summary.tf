resource "kubectl_manifest" "teleport_inference_model" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportInferenceModel"
    metadata = {
      name      = "bedrock-claude-sonnet"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      bedrock = {
        bedrock_model_id = "us.anthropic.claude-sonnet-4-6"
        region           = "us-west-2"
      }
    }
  })

  depends_on = [helm_release.teleport_cluster]
}

resource "kubectl_manifest" "teleport_inference_policy" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportInferencePolicy"
    metadata = {
      name      = "session-summary-policy"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      model = "bedrock-claude-sonnet"
      kinds = ["ssh", "k8s", "db"]
    }
  })

  depends_on = [helm_release.teleport_cluster]
}
