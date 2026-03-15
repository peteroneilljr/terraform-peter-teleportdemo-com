resource "kubernetes_namespace_v1" "coder" {
  metadata { name = "psh-coder" }
}

resource "kubernetes_secret_v1" "coder_db_url" {
  metadata {
    name      = "coder-db-url"
    namespace = kubernetes_namespace_v1.coder.metadata[0].name
  }
  data = {
    url = "postgres://coder:${random_password.coder_db.result}@${module.postgres.helm_release_name}-postgresql.${module.postgres.helm_release_namespace}.svc.cluster.local:5432/coder?sslmode=require"
  }
}

resource "helm_release" "coder" {
  name       = "coder"
  namespace  = kubernetes_namespace_v1.coder.metadata[0].name
  repository = "https://helm.coder.com/v2"
  chart      = "coder"

  wait = false

  values = [yamlencode({
    coder = {
      resources = {
        requests = { cpu = "1000m", memory = "2Gi" }
      }
      service = { type = "ClusterIP" }
      env = [
        { name = "CODER_PG_CONNECTION_URL", valueFrom = { secretKeyRef = { name = kubernetes_secret_v1.coder_db_url.metadata[0].name, key = "url" } } },
        { name = "CODER_ACCESS_URL", value = "https://coder.${local.teleport_cluster_fqdn}" },
        { name = "CODER_WILDCARD_ACCESS_URL", value = "*.coder.${local.teleport_cluster_fqdn}" },
        { name = "CODER_OAUTH2_GITHUB_CLIENT_ID", value = var.coder_github_client_id },
        { name = "CODER_OAUTH2_GITHUB_CLIENT_SECRET", value = var.coder_github_client_secret },
        { name = "CODER_OAUTH2_GITHUB_ALLOWED_ORGS", value = var.github_org },
        { name = "CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS", value = "true" },
      ]
    }
  })]

  depends_on = [kubernetes_secret_v1.coder_db_url]
}

resource "kubectl_manifest" "teleport_role_coder" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "${var.resource_prefix}coder"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        app_labels = {
          app = "coder"
        }
      }
    }
  })
}

# ---------------------------------------------------------------------------- #
# Coder Template: Kubernetes
# ---------------------------------------------------------------------------- #
locals {
  coder_template_dir  = "${path.module}/coder-templates/kubernetes"
  coder_template_hash = md5(file("${local.coder_template_dir}/main.tf"))
}

resource "kubernetes_config_map_v1" "coder_template_kubernetes" {
  metadata {
    name      = "coder-template-kubernetes"
    namespace = kubernetes_namespace_v1.coder.metadata[0].name
  }
  data = {
    "main.tf" = file("${local.coder_template_dir}/main.tf")
  }
}

resource "kubernetes_secret_v1" "coder_session_token" {
  metadata {
    name      = "coder-session-token"
    namespace = kubernetes_namespace_v1.coder.metadata[0].name
  }
  data = {
    token = var.coder_session_token
  }
}

resource "kubernetes_job_v1" "coder_template_push" {
  metadata {
    name      = "coder-template-push-${substr(local.coder_template_hash, 0, 8)}"
    namespace = kubernetes_namespace_v1.coder.metadata[0].name
  }

  spec {
    backoff_limit = 3
    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "coder-template-push"
        }
      }
      spec {
        restart_policy = "OnFailure"

        init_container {
          name    = "wait-for-coder"
          image   = "ubuntu:24.04"
          command = ["bash", "-c", "apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && until curl -sf http://coder.${kubernetes_namespace_v1.coder.metadata[0].name}.svc.cluster.local/api/v2/buildinfo; do echo 'Waiting for Coder...'; sleep 5; done"]
        }

        container {
          name  = "push-template"
          image = "ubuntu:24.04"
          command = ["bash", "-c", <<-EOT
            set -ex
            apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1
            CODER_URL="http://coder.${kubernetes_namespace_v1.coder.metadata[0].name}.svc.cluster.local"

            # Download Coder CLI
            curl -fsSL "$CODER_URL/bin/coder-linux-amd64" -o /tmp/coder
            chmod +x /tmp/coder

            # Login
            /tmp/coder login --token "$CODER_SESSION_TOKEN" "$CODER_URL"

            # Copy template files from ConfigMap mount (symlinks) to a regular directory
            mkdir -p /tmp/template
            cp /templates/* /tmp/template/
            ls -la /tmp/template/

            # Push template (creates if new, updates if exists)
            /tmp/coder templates push kubernetes -d /tmp/template --yes
          EOT
          ]
          env {
            name = "CODER_SESSION_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.coder_session_token.metadata[0].name
                key  = "token"
              }
            }
          }
          volume_mount {
            name       = "template"
            mount_path = "/templates"
            read_only  = true
          }
        }

        volume {
          name = "template"
          config_map {
            name = kubernetes_config_map_v1.coder_template_kubernetes.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = false

  depends_on = [helm_release.coder]

  lifecycle {
    replace_triggered_by = [kubernetes_config_map_v1.coder_template_kubernetes]
  }
}

resource "kubernetes_cluster_role_binding" "coder" {
  metadata { name = "coder-workspace-manager" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "coder"
    namespace = kubernetes_namespace_v1.coder.metadata[0].name
  }
}
