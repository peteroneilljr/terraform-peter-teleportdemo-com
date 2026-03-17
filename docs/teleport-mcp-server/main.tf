# Teleport MCP Server — Terraform configuration
#
# Deploys a Python MCP server in-cluster that exposes Teleport admin operations
# as MCP tools for Claude Code and other MCP-compatible AI agents.
#
# Architecture:
#   tbot sidecar (Machine ID) authenticates to Teleport using the Kubernetes join
#   method, writing short-lived identity credentials to a shared emptyDir volume.
#   The Python MCP server reads those credentials and shells out to tctl, exposing
#   tools like list-nodes, approve-access-request, create-lock, etc. over the MCP
#   protocol on port 8011. Teleport proxies it as an App (mcp+http URI scheme) so
#   MCP clients connect through Teleport's access controls.
#
# Flow:
#   MCP client → tsh mcp connect (stdio↔HTTP bridge)
#     → Teleport App Proxy (mcp+http, enforces MCP RBAC)
#       → teleport-mcp K8s Service :8011
#         → Python MCP server (FastMCP stateless streamable-http)
#           → tctl (using tbot identity from /opt/machine-id/identity)
#             → Teleport Auth Server
#
# RBAC note: The local mcp-client role requires BOTH app_labels AND mcp.tools
# permissions. Without mcp.tools, Teleport's MCP proxy returns null for tools/list
# and denies all tools/call requests. See the README for details.
#
# Prerequisites:
#   - Teleport Kubernetes operator installed in var.teleport_operator_namespace
#   - Teleport kube-agent with appResources enabled (auto-discovers TeleportAppV3 CRDs)
#   - Teleport v18.7+
#   - Providers: kubernetes, kubectl, random

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

# ---------------------------------------------------------------------------- #
# Namespace + ServiceAccount
# ---------------------------------------------------------------------------- #

resource "kubernetes_namespace_v1" "teleport_mcp" {
  metadata {
    name = var.namespace
  }
}

# Service account used by the tbot sidecar for the Kubernetes join method.
# The provision token references this service account by namespace:name.
resource "kubernetes_service_account_v1" "teleport_mcp_tbot" {
  metadata {
    name      = "teleport-mcp-tbot"
    namespace = kubernetes_namespace_v1.teleport_mcp.metadata[0].name
  }
}

# ---------------------------------------------------------------------------- #
# Teleport CRDs — placed in the operator namespace so the Teleport operator
# picks them up and creates the corresponding resources in the auth server.
# ---------------------------------------------------------------------------- #

# Role: broad read/write access on all Teleport resource types for the server-side bot.
# This is the admin identity used by tctl inside the pod — scope it down if needed.
resource "kubectl_manifest" "teleport_role_mcp_admin" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "mcp-admin"
      namespace  = var.teleport_operator_namespace
    }
    spec = {
      allow = {
        rules = [
          {
            resources = [
              "node", "app_server", "db_server", "kube_cluster", "role", "user",
              "access_request", "event", "session", "lock", "token", "bot",
              "windows_desktop", "saml_connector", "oidc_connector", "github_connector",
              "cluster_auth_preference", "access_list"
            ]
            verbs = ["list", "read", "create", "update", "delete"]
          }
        ]
      }
    }
  })
}

# Provision token: Kubernetes join method so tbot authenticates via service account JWT.
# No static secret — the join is validated by the Kubernetes OIDC token.
resource "kubectl_manifest" "teleport_mcp_token" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportProvisionToken"
    metadata = {
      name      = "mcp-bot"
      namespace = var.teleport_operator_namespace
    }
    spec = {
      roles       = ["Bot"]
      bot_name    = "mcp-admin"
      join_method = "kubernetes"
      kubernetes = {
        type = "in_cluster"
        allow = [
          {
            # Format: "<namespace>:<service-account-name>"
            service_account = "${var.namespace}:teleport-mcp-tbot"
          }
        ]
      }
    }
  })
}

# Bot identity — binds the mcp-admin role to the machine identity used by tbot.
resource "kubectl_manifest" "teleport_bot_mcp_admin" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportBotV1"
    metadata = {
      name      = "mcp-admin"
      namespace = var.teleport_operator_namespace
    }
    spec = {
      roles = ["mcp-admin"]
    }
  })

  depends_on = [kubectl_manifest.teleport_role_mcp_admin]
}

# App registration — exposes the MCP server through Teleport's app proxy.
# Requires kube-agent with appResources enabled to discover this CRD automatically.
resource "kubectl_manifest" "teleport_app_mcp" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "teleport-mcp"
      namespace = var.teleport_operator_namespace
      labels    = var.app_labels
    }
    spec = {
      # mcp+http tells Teleport to proxy this as an MCP application.
      # The path must end in /mcp (FastMCP's default route).
      uri = "mcp+http://${kubernetes_service_v1.teleport_mcp.metadata[0].name}.${var.namespace}.svc.cluster.local:8011/mcp"
    }
  })

  depends_on = [kubernetes_service_v1.teleport_mcp]
}

# ---------------------------------------------------------------------------- #
# ConfigMaps
# ---------------------------------------------------------------------------- #

# tbot configuration — Kubernetes join method, writes identity to shared volume.
resource "kubernetes_config_map" "teleport_mcp_tbot" {
  metadata {
    name      = "teleport-mcp-tbot"
    namespace = kubernetes_namespace_v1.teleport_mcp.metadata[0].name
  }

  data = {
    "tbot.yaml" = yamlencode({
      version      = "v2"
      proxy_server = "${var.teleport_cluster_fqdn}:443"
      onboarding = {
        join_method = "kubernetes"
        token       = "mcp-bot"
      }
      storage = {
        # Memory storage — no persistent volume needed. tbot re-authenticates
        # on restart using the Kubernetes service account JWT.
        type = "memory"
      }
      services = [
        {
          type = "identity"
          destination = {
            type = "directory"
            path = "/opt/machine-id"
          }
        }
      ]
    })
  }
}

# MCP server Python script — mounted into the mcp-server container.
# See files/server.py for the implementation.
resource "kubernetes_config_map" "teleport_mcp_server" {
  metadata {
    name      = "teleport-mcp-server"
    namespace = kubernetes_namespace_v1.teleport_mcp.metadata[0].name
  }

  data = {
    "server.py" = file("${path.module}/files/server.py")
  }
}

# ---------------------------------------------------------------------------- #
# Deployment
# ---------------------------------------------------------------------------- #

resource "kubernetes_deployment_v1" "teleport_mcp" {
  metadata {
    name      = "teleport-mcp"
    namespace = kubernetes_namespace_v1.teleport_mcp.metadata[0].name
    labels    = { app = "teleport-mcp" }
  }

  # Don't block terraform apply waiting for rollout — the first deploy
  # takes a few minutes while tctl is downloaded in the init step.
  wait_for_rollout = false

  spec {
    replicas = 1

    selector {
      match_labels = { app = "teleport-mcp" }
    }

    template {
      metadata {
        labels = { app = "teleport-mcp" }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.teleport_mcp_tbot.metadata[0].name

        # tbot sidecar — authenticates via Kubernetes service account JWT and
        # continuously renews machine identity credentials into /opt/machine-id.
        container {
          name    = "tbot"
          image   = "public.ecr.aws/gravitational/teleport-distroless:${var.teleport_version}"
          command = ["/usr/bin/dumb-init", "tbot", "start", "-c", "/etc/tbot/tbot.yaml"]

          volume_mount {
            name       = "tbot-config"
            mount_path = "/etc/tbot"
            read_only  = true
          }

          volume_mount {
            name       = "machine-id"
            mount_path = "/opt/machine-id"
          }
        }

        # MCP server — serves stateless streamable-http on port 8011.
        # Stateless mode is required because Teleport's mcp+http proxy doesn't
        # preserve session IDs across requests.
        #
        # The startup command installs curl, downloads tctl from the Teleport CDN,
        # installs the mcp Python package, then starts the server. tctl is downloaded
        # at runtime because the distroless Teleport image provides no shell or cp
        # command that would work in an init container, and a non-distroless ECR image
        # isn't available.
        container {
          name  = "mcp-server"
          image = "python:3.12-slim"
          command = [
            "/bin/sh", "-c",
            "apt-get update && apt-get install -y --no-install-recommends curl && curl -fsSL https://cdn.teleport.dev/teleport-v${var.teleport_version}-linux-amd64-bin.tar.gz | tar xz -C /tmp && mv /tmp/teleport/tctl /opt/teleport-bin/tctl && rm -rf /tmp/teleport && pip install --no-cache-dir mcp && exec python3 /opt/mcp/server.py"
          ]

          port {
            container_port = 8011
            name           = "mcp"
          }

          env {
            name  = "TELEPORT_PROXY"
            value = "${var.teleport_cluster_fqdn}:443"
          }

          env {
            name  = "TELEPORT_IDENTITY"
            value = "/opt/machine-id/identity"
          }

          env {
            name  = "TCTL_PATH"
            value = "/opt/teleport-bin/tctl"
          }

          volume_mount {
            name       = "machine-id"
            mount_path = "/opt/machine-id"
            read_only  = true
          }

          volume_mount {
            name       = "teleport-bin"
            mount_path = "/opt/teleport-bin"
          }

          volume_mount {
            name       = "mcp-server"
            mount_path = "/opt/mcp"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "machine-id"
          empty_dir {}
        }

        volume {
          name = "teleport-bin"
          empty_dir {}
        }

        volume {
          name = "tbot-config"
          config_map {
            name = kubernetes_config_map.teleport_mcp_tbot.metadata[0].name
          }
        }

        volume {
          name = "mcp-server"
          config_map {
            name = kubernetes_config_map.teleport_mcp_server.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubectl_manifest.teleport_bot_mcp_admin,
    kubectl_manifest.teleport_mcp_token,
    kubernetes_config_map.teleport_mcp_tbot,
    kubernetes_config_map.teleport_mcp_server,
  ]
}

# ---------------------------------------------------------------------------- #
# Service
# ---------------------------------------------------------------------------- #

resource "kubernetes_service_v1" "teleport_mcp" {
  metadata {
    name      = "teleport-mcp"
    namespace = kubernetes_namespace_v1.teleport_mcp.metadata[0].name
    labels    = { app = "teleport-mcp" }
  }

  spec {
    selector = { app = "teleport-mcp" }

    port {
      port        = 8011
      target_port = 8011
      name        = "mcp"
    }
  }
}

# ---------------------------------------------------------------------------- #
# Local MCP Client Bot — provides the identity for `tsh mcp connect` on
# developer machines. Uses static token join (no Kubernetes service account
# available locally).
#
# The client identity only needs app access to reach the MCP server through
# Teleport's proxy; the actual tctl admin calls happen server-side via the
# in-cluster mcp-admin bot.
# ---------------------------------------------------------------------------- #

# Role: app access + MCP tool permissions.
# CRITICAL: mcp.tools is required by Teleport's MCP proxy RBAC (v18.7+).
# Without it, tools/list returns null and tools/call is denied with:
#   "RBAC is enforced by your Teleport roles"
resource "kubectl_manifest" "teleport_role_mcp_client" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "mcp-client"
      namespace  = var.teleport_operator_namespace
    }
    spec = {
      allow = {
        app_labels = {
          "*" = "*"
        }
        # MCP tool access — required by Teleport's MCP proxy RBAC.
        # Without this block, tools/list returns null and all tool calls are denied.
        mcp = {
          tools = ["*"]
        }
      }
    }
  })
}

# Token value — the token name IS the join secret for the static token method.
# upper = false enforces RFC 1123 compliance (lowercase alphanumeric only).
resource "random_password" "mcp_client_token" {
  length  = 32
  special = false
  upper   = false
}

resource "kubectl_manifest" "teleport_mcp_client_token" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportProvisionToken"
    metadata = {
      # The token name is the secret value — it's what tbot uses in its config.
      name      = random_password.mcp_client_token.result
      namespace = var.teleport_operator_namespace
    }
    spec = {
      roles       = ["Bot"]
      bot_name    = "mcp-client"
      join_method = "token"
    }
  })
}

resource "kubectl_manifest" "teleport_bot_mcp_client" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportBotV1"
    metadata = {
      name      = "mcp-client"
      namespace = var.teleport_operator_namespace
    }
    spec = {
      roles = ["mcp-client"]
    }
  })

  depends_on = [kubectl_manifest.teleport_role_mcp_client]
}
