terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {
  url = "http://coder.psh-coder.svc.cluster.local"
}

provider "kubernetes" {
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

variable "use_kubeconfig" {
  type    = bool
  default = false
}

variable "namespace" {
  type    = string
  default = "psh-coder"
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key (https://console.anthropic.com/settings/keys)"
  sensitive   = true
}

# ---------------------------------------------------------------------------- #
# Task plumbing
# ---------------------------------------------------------------------------- #

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_task" "me" {}

module "claude-code" {
  source         = "registry.coder.com/coder/claude-code/coder"
  version        = "4.0.0"
  agent_id       = coder_agent.main.id
  workdir        = "/home/coder"
  claude_api_key = var.anthropic_api_key
  ai_prompt      = data.coder_task.me.prompt
  model          = "sonnet"
}

resource "coder_ai_task" "task" {
  app_id = module.claude-code.task_app_id
}

# ---------------------------------------------------------------------------- #
# Agent
# ---------------------------------------------------------------------------- #

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
}

# ---------------------------------------------------------------------------- #
# Workspace pod
# ---------------------------------------------------------------------------- #

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "10Gi" }
    }
  }
}

resource "kubernetes_deployment_v1" "main" {
  count            = data.coder_workspace.me.start_count
  depends_on       = [kubernetes_persistent_volume_claim_v1.home]
  wait_for_rollout = false

  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "coder-workspace"
        "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
        "app.kubernetes.io/part-of"  = "coder"
        "com.coder.resource"         = "true"
        "com.coder.workspace.id"     = data.coder_workspace.me.id
        "com.coder.workspace.name"   = data.coder_workspace.me.name
        "com.coder.user.id"          = data.coder_workspace_owner.me.id
        "com.coder.user.username"    = data.coder_workspace_owner.me.name
      }
    }
    strategy { type = "Recreate" }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
          "app.kubernetes.io/part-of"  = "coder"
          "com.coder.resource"         = "true"
          "com.coder.workspace.id"     = data.coder_workspace.me.id
          "com.coder.workspace.name"   = data.coder_workspace.me.name
          "com.coder.user.id"          = data.coder_workspace_owner.me.id
          "com.coder.user.username"    = data.coder_workspace_owner.me.name
        }
      }
      spec {
        security_context {
          run_as_user     = 1000
          fs_group        = 1000
          run_as_non_root = true
        }

        container {
          name              = "dev"
          image             = "codercom/enterprise-base:ubuntu"
          image_pull_policy = "Always"
          # Custom init script instead of coder_agent.main.init_script.
          # Coder stamps CODER_ACCESS_URL (the Teleport app proxy URL) into the
          # default init script for both binary download and agent connection.
          # Unauthenticated requests to the proxy return an HTML login page, not
          # the binary. Neither `provider "coder" { url = "..." }` nor the
          # server-side CODER_AGENT_URL env var override this behavior.
          # See: https://github.com/coder/coder/discussions/23048
          command = ["sh", "-c", <<-EOT
            set -eux
            CODER_URL="http://coder.psh-coder.svc.cluster.local"

            curl -fsSL "$CODER_URL/bin/coder-linux-amd64" -o /tmp/coder
            chmod +x /tmp/coder

            export CODER_AGENT_AUTH="token"
            export CODER_AGENT_URL="$CODER_URL"
            exec /tmp/coder agent
          EOT
          ]
          security_context {
            run_as_user = "1000"
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          resources {
            requests = {
              "cpu"    = "500m"
              "memory" = "1Gi"
            }
            limits = {
              "cpu"    = "4"
              "memory" = "4Gi"
            }
          }
          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata.0.name
            read_only  = false
          }
        }
      }
    }
  }
}
