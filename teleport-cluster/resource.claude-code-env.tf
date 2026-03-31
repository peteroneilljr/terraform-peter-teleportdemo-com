# Claude Code Environment — isolated pod with Teleport SSH access, tbot sidecar,
# and Claude Code runtime. Deployed as a Helm chart; CRDs managed here in Terraform.
#
# Architecture:
#   Pod contains 3 containers:
#   - tbot: authenticates via K8s join method, writes identity to shared emptyDir
#   - teleport-agent: registers as SSH node so users can `tsh ssh` into the env
#   - claude-code: runs Claude Code CLI with MCP servers configured via settings.json

# ---------------------------------------------------------------------------- #
# Namespace
# ---------------------------------------------------------------------------- #

resource "kubernetes_namespace_v1" "claude_code_env" {
  metadata {
    name = "psh-claude-code-env"
  }
}

# ---------------------------------------------------------------------------- #
# Teleport CRDs
# ---------------------------------------------------------------------------- #

# Role for the Claude Code bot — needs SSH node registration + MCP app access
resource "kubectl_manifest" "teleport_role_claude_code_bot" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "claude-code-bot"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        app_labels = {
          "*" = "*"
        }
        mcp = {
          tools = ["*"]
        }
        node_labels = {
          "*" = "*"
        }
        rules = [
          {
            resources = ["node", "app_server"]
            verbs     = ["list", "read", "create", "update"]
          }
        ]
      }
    }
  })
}

# Provision token — kubernetes join method so tbot authenticates via service account JWT
resource "kubectl_manifest" "teleport_claude_code_token" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportProvisionToken"
    metadata = {
      name      = "claude-code-bot"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles       = ["Bot"]
      bot_name    = "claude-code-bot"
      join_method = "kubernetes"
      kubernetes = {
        type = "in_cluster"
        allow = [
          {
            service_account = "psh-claude-code-env:claude-code-env-tbot"
          }
        ]
      }
    }
  })

  depends_on = [helm_release.teleport_cluster]
}

# Bot identity — references the claude-code-bot role
resource "kubectl_manifest" "teleport_bot_claude_code" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportBotV1"
    metadata = {
      name      = "claude-code-bot"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles = ["claude-code-bot"]
    }
  })

  depends_on = [
    kubectl_manifest.teleport_role_claude_code_bot,
  ]
}

# Provision token for the SSH node agent — kubernetes join method, Node role
resource "kubectl_manifest" "teleport_claude_code_node_token" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportProvisionToken"
    metadata = {
      name      = "claude-code-node"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles       = ["Node"]
      join_method = "kubernetes"
      kubernetes = {
        type = "in_cluster"
        allow = [
          {
            service_account = "psh-claude-code-env:claude-code-env-tbot"
          }
        ]
      }
    }
  })

  depends_on = [helm_release.teleport_cluster]
}

# ---------------------------------------------------------------------------- #
# Kubernetes Secret for Anthropic API Key
# ---------------------------------------------------------------------------- #

resource "kubernetes_secret_v1" "claude_code_anthropic_key" {
  metadata {
    name      = "anthropic-api-key"
    namespace = kubernetes_namespace_v1.claude_code_env.metadata[0].name
  }

  data = {
    "api-key" = var.anthropic_api_key
  }
}

# ---------------------------------------------------------------------------- #
# Helm Release
# ---------------------------------------------------------------------------- #

resource "helm_release" "claude_code_env" {
  name      = "claude-code-env"
  namespace = kubernetes_namespace_v1.claude_code_env.metadata[0].name
  chart     = "${path.module}/../helm-charts/claude-code-env"

  wait = false

  values = [yamlencode({
    teleport = {
      proxyAddr     = "${local.teleport_cluster_fqdn}:443"
      version       = var.teleport_version
      botTokenName  = "claude-code-bot"
      nodeTokenName = "claude-code-node"
    }
    anthropicApiKey = {
      secretName = kubernetes_secret_v1.claude_code_anthropic_key.metadata[0].name
      secretKey  = "api-key"
    }
  })]

  depends_on = [
    helm_release.teleport_cluster,
    kubectl_manifest.teleport_bot_claude_code,
    kubectl_manifest.teleport_claude_code_token,
    kubectl_manifest.teleport_claude_code_node_token,
    kubernetes_secret_v1.claude_code_anthropic_key,
  ]
}
