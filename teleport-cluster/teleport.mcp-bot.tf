# Teleport MCP Server — exposes Teleport resources via MCP protocol for AI agents
#
# Architecture:
#   tbot sidecar (Machine ID) authenticates to Teleport using Kubernetes join method,
#   writes short-lived identity credentials to a shared emptyDir volume. The MCP server
#   reads those credentials to make tctl calls against the Teleport cluster, exposing
#   tools like list-nodes, list-apps, list-users, etc. over the MCP protocol.
#
#   The Python MCP server uses FastMCP's stateless streamable-http transport directly
#   on port 8011. Teleport proxies it as an App (mcp+http URI scheme) so Claude and
#   other MCP clients can connect through Teleport's access controls.
#
# Flow: MCP client → Teleport App Proxy → teleport-mcp service:8011 → Python MCP
#       server (streamable-http) → tctl (using tbot identity from /opt/machine-id/identity)
#
# RBAC note: The local mcp-client role requires both app_labels AND mcp.tools
# permissions. Without mcp.tools, Teleport's MCP proxy returns null tools and
# blocks all tool calls.

# ---------------------------------------------------------------------------- #
# Namespace + ServiceAccount
# ---------------------------------------------------------------------------- #

resource "kubernetes_namespace_v1" "teleport_mcp" {
  metadata {
    name = "psh-teleport-mcp"
  }
}

resource "kubernetes_service_account_v1" "teleport_mcp_tbot" {
  metadata {
    name      = "teleport-mcp-tbot"
    namespace = kubernetes_namespace_v1.teleport_mcp.metadata[0].name
  }
}

# ---------------------------------------------------------------------------- #
# Teleport CRDs — created manually because the operator watches psh-cluster,
# but the MCP server runs in psh-teleport-mcp.
# ---------------------------------------------------------------------------- #

# Role granting broad read/write access to Teleport resources for the MCP bot
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
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        # Label-based access — required for tctl nodes/apps/db/kube ls commands
        node_labels       = { "*" = "*" }
        app_labels        = { "*" = "*" }
        db_labels         = { "*" = "*" }
        kubernetes_labels = { "*" = "*" }
        # API-level RBAC
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

# Provision token — kubernetes join method so tbot authenticates via service account JWT
resource "kubectl_manifest" "teleport_mcp_token" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportProvisionToken"
    metadata = {
      name      = "mcp-bot"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles       = ["Bot"]
      bot_name    = "mcp-admin"
      join_method = "kubernetes"
      kubernetes = {
        type = "in_cluster"
        allow = [
          {
            service_account = "psh-teleport-mcp:teleport-mcp-tbot"
          }
        ]
      }
    }
  })

  depends_on = [helm_release.teleport_cluster]
}

# Bot identity — references the mcp-admin role
resource "kubectl_manifest" "teleport_bot_mcp_admin" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportBotV1"
    metadata = {
      name      = "mcp-admin"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles = ["mcp-admin"]
    }
  })

  depends_on = [
    kubectl_manifest.teleport_role_mcp_admin,
  ]
}

# App registration — exposes the MCP server through Teleport's app proxy
resource "kubectl_manifest" "teleport_app_mcp" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAppV3"
    metadata = {
      name      = "teleport-mcp"
      namespace = helm_release.teleport_cluster.namespace
      labels    = { env = "dev", host = "k8s" }
    }
    spec = {
      uri = "mcp+http://teleport-mcp.psh-teleport-mcp.svc.cluster.local:8011/mcp"
    }
  })
}

# ---------------------------------------------------------------------------- #
# ConfigMaps
# ---------------------------------------------------------------------------- #

# tbot configuration — uses Kubernetes join method with the mcp-bot token
resource "kubernetes_config_map" "teleport_mcp_tbot" {
  metadata {
    name      = "teleport-mcp-tbot"
    namespace = kubernetes_namespace_v1.teleport_mcp.metadata[0].name
  }

  data = {
    "tbot.yaml" = yamlencode({
      version      = "v2"
      proxy_server = "${local.teleport_cluster_fqdn}:443"
      onboarding = {
        join_method = "kubernetes"
        token       = "mcp-bot"
      }
      storage = {
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

# MCP server Python script — loaded from files/teleport-mcp-server.py
resource "kubernetes_config_map" "teleport_mcp_server" {
  metadata {
    name      = "teleport-mcp-server"
    namespace = kubernetes_namespace_v1.teleport_mcp.metadata[0].name
  }

  data = {
    "server.py" = file("${path.module}/files/teleport-mcp-server.py")
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
          name  = "tbot"
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

        # MCP server — serves stateless streamable-http directly on port 8011.
        # Stateless mode is required because Teleport's mcp+http proxy doesn't
        # preserve session IDs across requests.
        container {
          name    = "mcp-server"
          image   = "python:3.12-slim"
          # Install tctl from Teleport CDN, install Python deps, then start the MCP server.
          # tctl is downloaded here because the distroless Teleport image has no shell/cp
          # to use in an init container, and the non-distroless image doesn't exist on ECR public.
          command = ["/bin/sh", "-c", "apt-get update && apt-get install -y --no-install-recommends curl && curl -fsSL https://cdn.teleport.dev/teleport-v${var.teleport_version}-linux-amd64-bin.tar.gz | tar xz -C /tmp && mv /tmp/teleport/tctl /opt/teleport-bin/tctl && rm -rf /tmp/teleport && pip install --no-cache-dir mcp && exec python3 /opt/mcp/server.py"]

          port {
            container_port = 8011
            name           = "mcp"
          }

          env {
            name  = "TELEPORT_PROXY"
            value = "${local.teleport_cluster_fqdn}:443"
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
              cpu    = "25m"
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
    helm_release.teleport_cluster,
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
# Local MCP Client Bot — provides identity for tsh mcp connect on developer
# machines. Uses token join method (no k8s service account available locally).
# The identity only needs app access to reach teleport-mcp through the proxy;
# the actual admin tctl calls happen server-side via the in-cluster bot above.
# ---------------------------------------------------------------------------- #

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
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        app_labels = {
          "*" = "*"
        }
        # MCP tool access — required by Teleport's MCP proxy RBAC.
        # Without this, tools/list returns null and tools/call is denied.
        mcp = {
          tools = ["*"]
        }
      }
    }
  })
}

# Random token value — used as the provision token name (which IS the join secret)
resource "random_password" "mcp_client_token" {
  length  = 32
  special = false
  upper   = false # token name must be lowercase RFC 1123
}

resource "kubectl_manifest" "teleport_mcp_client_token" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportProvisionToken"
    metadata = {
      name      = random_password.mcp_client_token.result
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles       = ["Bot"]
      bot_name    = "mcp-client"
      join_method = "token"
    }
  })

  depends_on = [helm_release.teleport_cluster]
}

resource "kubectl_manifest" "teleport_bot_mcp_client" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportBotV1"
    metadata = {
      name      = "mcp-client"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles = ["mcp-client"]
    }
  })

  depends_on = [
    kubectl_manifest.teleport_role_mcp_client,
  ]
}

# Output the token value so we can configure the local tbot
output "mcp_client_join_token" {
  value     = random_password.mcp_client_token.result
  sensitive = true
}
