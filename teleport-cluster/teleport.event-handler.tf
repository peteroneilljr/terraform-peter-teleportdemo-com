# Teleport Event Handler — exports audit events to Elasticsearch via Logstash
#
# Pipeline: Teleport Auth (gRPC) → Event Handler Plugin → HTTPS/mTLS → Logstash → Elasticsearch → Kibana
#
# The event handler connects to Teleport's auth server over gRPC, receives audit
# events, and forwards them to Logstash over HTTPS with mutual TLS. Logstash then
# indexes them into Elasticsearch where they're queryable via Kibana.
#
# Docs: https://goteleport.com/docs/zero-trust-access/export-audit-events/elastic-stack/

# ---------------------------------------------------------------------------- #
# mTLS Certificates (self-signed CA + server cert for Logstash + client cert
# for the event handler). Follows the same pattern as teleport.access-graph.tf.
# ---------------------------------------------------------------------------- #

resource "tls_private_key" "event_handler_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "event_handler_ca" {
  private_key_pem = tls_private_key.event_handler_ca.private_key_pem

  subject {
    common_name  = "Event Handler CA"
    organization = "Teleport"
  }

  is_ca_certificate     = true
  validity_period_hours = 87600 # 10 years
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

# Server certificate — used by Logstash for its HTTPS listener
resource "tls_private_key" "event_handler_server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "event_handler_server" {
  private_key_pem = tls_private_key.event_handler_server.private_key_pem

  subject {
    common_name  = "Logstash"
    organization = "Teleport"
  }

  dns_names = [
    "logstash.psh-elasticsearch.svc.cluster.local",
  ]
}

resource "tls_locally_signed_cert" "event_handler_server" {
  cert_request_pem   = tls_cert_request.event_handler_server.cert_request_pem
  ca_private_key_pem = tls_private_key.event_handler_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.event_handler_ca.cert_pem

  validity_period_hours = 87600 # 10 years
  allowed_uses = [
    "server_auth",
    "key_encipherment",
    "digital_signature",
  ]
}

# Client certificate — used by the event handler to authenticate to Logstash
resource "tls_private_key" "event_handler_client" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "event_handler_client" {
  private_key_pem = tls_private_key.event_handler_client.private_key_pem

  subject {
    common_name  = "event-handler"
    organization = "Teleport"
  }
}

resource "tls_locally_signed_cert" "event_handler_client" {
  cert_request_pem   = tls_cert_request.event_handler_client.cert_request_pem
  ca_private_key_pem = tls_private_key.event_handler_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.event_handler_ca.cert_pem

  validity_period_hours = 87600 # 10 years
  allowed_uses = [
    "client_auth",
    "key_encipherment",
    "digital_signature",
  ]
}

# ---------------------------------------------------------------------------- #
# Kubernetes Secrets (in psh-elasticsearch namespace)
# ---------------------------------------------------------------------------- #

# Client TLS secret — mounted by the event handler Helm chart
resource "kubernetes_secret" "event_handler_client_tls" {
  metadata {
    name      = "event-handler-client-tls"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  }

  data = {
    "ca.crt"     = tls_self_signed_cert.event_handler_ca.cert_pem
    "client.crt" = tls_locally_signed_cert.event_handler_client.cert_pem
    "client.key" = tls_private_key.event_handler_client.private_key_pem
  }

  type = "Opaque"
}

# Server TLS secret — mounted by Logstash
resource "kubernetes_secret" "logstash_tls" {
  metadata {
    name      = "logstash-tls"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  }

  data = {
    "ca.crt"     = tls_self_signed_cert.event_handler_ca.cert_pem
    "server.crt" = tls_locally_signed_cert.event_handler_server.cert_pem
    "server.key" = tls_private_key.event_handler_server.private_key_pem_pkcs8
  }

  type = "Opaque"
}

# ---------------------------------------------------------------------------- #
# Elasticsearch User/Role for Audit Event Writes
# ---------------------------------------------------------------------------- #

resource "random_password" "event_handler_es" {
  length  = 16
  special = false
}

resource "kubernetes_config_map" "event_handler_es_seed" {
  metadata {
    name      = "event-handler-es-seed"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  }

  data = {
    "seed.sh" = <<-SCRIPT
      #!/bin/sh
      set -e
      ES_URL="https://elasticsearch-master:9200"

      echo "Waiting for Elasticsearch to be ready..."
      until curl -ksf -u "elastic:$ES_PASSWORD" "$ES_URL/_cluster/health" | grep -qE '"status":"(green|yellow)"'; do
        sleep 5
      done

      # Create role for the event handler — write access to audit-events-* indices
      echo "Creating teleport-event-handler role..."
      curl -ksf -u "elastic:$ES_PASSWORD" -X PUT "$ES_URL/_security/role/teleport-event-handler" \
        -H "Content-Type: application/json" \
        -d '{"cluster":["manage_index_templates","manage_ilm","monitor"],"indices":[{"names":["audit-events-*"],"privileges":["write","manage","create_index"]}]}'
      echo ""

      # Create user for the event handler
      echo "Creating teleport-event-handler user..."
      curl -ksf -u "elastic:$ES_PASSWORD" -X POST "$ES_URL/_security/user/teleport-event-handler" \
        -H "Content-Type: application/json" \
        -d "{\"password\":\"$EVENT_HANDLER_ES_PASSWORD\",\"roles\":[\"teleport-event-handler\"],\"full_name\":\"Teleport Event Handler\"}"
      echo ""

      # Create index template for audit events with dynamic mapping
      echo "Creating audit-events index template..."
      curl -ksf -u "elastic:$ES_PASSWORD" -X PUT "$ES_URL/_index_template/audit-events" \
        -H "Content-Type: application/json" \
        -d @/data/audit-events-template.json
      echo ""

      # Update the kibana_anonymous role to also grant read access to audit-events-*
      echo "Updating kibana_anonymous role with audit-events access..."
      curl -ksf -u "elastic:$ES_PASSWORD" -X PUT "$ES_URL/_security/role/kibana_anonymous" \
        -H "Content-Type: application/json" \
        -d '{"cluster":["monitor"],"indices":[{"names":["*"],"privileges":["read","view_index_metadata"]},{"names":["audit-events-*"],"privileges":["read","view_index_metadata"]}],"applications":[{"application":"kibana-.kibana","privileges":["feature_discover.all","feature_dashboard.all","feature_visualize.all"],"resources":["*"]}]}'
      echo ""

      # Create Kibana data view for audit events
      echo "Creating Kibana data view for audit events..."
      curl -ksf -u "elastic:$ES_PASSWORD" -X POST "http://kibana.psh-elasticsearch.svc.cluster.local:5601/api/data_views/data_view" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{"data_view":{"id":"audit-events","title":"audit-events-*","name":"Teleport Audit Events","timeFieldName":"time"}}' || true
      echo ""

      KIBANA_URL="http://kibana.psh-elasticsearch.svc.cluster.local:5601"
      KIBANA_AUTH="elastic:$ES_PASSWORD"

      # Wait for Kibana to be ready
      echo "Waiting for Kibana..."
      until curl -ksf -u "$KIBANA_AUTH" "$KIBANA_URL/api/status" | grep -q '"overall"'; do
        sleep 5
      done

      # Create saved search — shows recent audit events in a table
      echo "Creating saved search..."
      curl -ksf -u "$KIBANA_AUTH" -X POST "$KIBANA_URL/api/saved_objects/search/audit-events-search?overwrite=true" \
        -H "Content-Type: application/json" -H "kbn-xsrf: true" \
        -d '{"attributes":{"title":"Recent Audit Events","columns":["time","event","code","user","cluster_name"],"sort":[["time","desc"]],"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"audit-events\",\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"id":"audit-events","name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern"}]}'
      echo ""

      # Create the dashboard with embedded panels (inline visualizations using aggregation-based approach)
      echo "Creating dashboard..."
      curl -ksf -u "$KIBANA_AUTH" -X POST "$KIBANA_URL/api/saved_objects/dashboard/teleport-audit-dashboard?overwrite=true" \
        -H "Content-Type: application/json" -H "kbn-xsrf: true" \
        -d @/data/kibana-dashboard.json
      echo ""

      echo "Event handler ES seed complete."
    SCRIPT

    "audit-events-template.json" = <<-JSON
      {
        "index_patterns": ["audit-events-*"],
        "template": {
          "settings": {
            "number_of_shards": 1,
            "number_of_replicas": 0
          },
          "mappings": {
            "dynamic": true,
            "properties": {
              "time": { "type": "date" },
              "event": { "type": "keyword" },
              "code": { "type": "keyword" },
              "uid": { "type": "keyword" },
              "user": { "type": "keyword" },
              "login": { "type": "keyword" },
              "namespace": { "type": "keyword" },
              "server_id": { "type": "keyword" },
              "addr.remote": { "type": "keyword" },
              "addr.local": { "type": "keyword" },
              "cluster_name": { "type": "keyword" },
              "success": { "type": "boolean" }
            }
          }
        },
        "priority": 100
      }
    JSON

    # Kibana dashboard saved object with inline search panel. Uses by-reference
    # saved search panel so Kibana renders the event log table directly.
    "kibana-dashboard.json" = jsonencode({
      attributes = {
        title       = "Teleport Audit Events"
        description = "Teleport cluster audit events streamed via the Event Handler plugin"
        timeRestore = true
        timeTo      = "now"
        timeFrom    = "now-24h"
        panelsJSON = jsonencode([
          {
            version  = "8.5.1"
            type     = "search"
            gridData = { x = 0, y = 0, w = 48, h = 24, i = "1" }
            panelIndex = "1"
            embeddableConfig = {
              enhancements = {}
            }
            panelRefName = "panel_1"
          }
        ])
        kibanaSavedObjectMeta = {
          searchSourceJSON = jsonencode({
            query  = { query = "", language = "kuery" }
            filter = []
          })
        }
      }
      references = [
        {
          id   = "audit-events-search"
          name = "panel_1"
          type = "search"
        }
      ]
    })
  }
}

resource "kubernetes_job" "event_handler_es_seed" {
  metadata {
    name      = "event-handler-es-seed"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  }

  spec {
    backoff_limit = 3

    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"

        container {
          name    = "seed"
          image   = "curlimages/curl:latest"
          command = ["/bin/sh", "/scripts/seed.sh"]

          env {
            name  = "ES_PASSWORD"
            value = random_password.elasticsearch.result
          }

          env {
            name  = "EVENT_HANDLER_ES_PASSWORD"
            value = random_password.event_handler_es.result
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.event_handler_es_seed.metadata[0].name
            default_mode = "0755"
            items {
              key  = "seed.sh"
              path = "seed.sh"
            }
          }
        }

        volume {
          name = "data"
          config_map {
            name = kubernetes_config_map.event_handler_es_seed.metadata[0].name
            items {
              key  = "audit-events-template.json"
              path = "audit-events-template.json"
            }
            items {
              key  = "kibana-dashboard.json"
              path = "kibana-dashboard.json"
            }
          }
        }
      }
    }
  }

  wait_for_completion = false

  depends_on = [helm_release.elasticsearch]
}

# ---------------------------------------------------------------------------- #
# Logstash — receives events from the event handler over HTTPS/mTLS and
# forwards them to Elasticsearch. Deployed as plain K8s resources (like Kibana).
# ---------------------------------------------------------------------------- #

resource "kubernetes_config_map" "logstash_config" {
  metadata {
    name      = "logstash-config"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  }

  data = {
    "logstash.yml" = <<-YAML
      http.host: "0.0.0.0"
      pipeline.ecs_compatibility: disabled
    YAML

    "pipelines.yml" = <<-YAML
      - pipeline.id: teleport-audit
        path.config: "/usr/share/logstash/pipeline/teleport-audit.conf"
    YAML
  }
}

resource "kubernetes_config_map" "logstash_pipeline" {
  metadata {
    name      = "logstash-pipeline"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  }

  data = {
    "teleport-audit.conf" = <<-CONF
      input {
        http {
          port => 9601
          ssl => true
          ssl_certificate => "/usr/share/logstash/tls/server.crt"
          ssl_key => "/usr/share/logstash/tls/server.key"
          ssl_certificate_authorities => ["/usr/share/logstash/tls/ca.crt"]
          ssl_verify_mode => "force_peer"
        }
      }

      output {
        elasticsearch {
          hosts => ["https://elasticsearch-master:9200"]
          user => "teleport-event-handler"
          password => "${random_password.event_handler_es.result}"
          ssl_certificate_verification => false
          index => "audit-events-%%{+yyyy.MM.dd}"
        }
      }
    CONF
  }
}

resource "kubernetes_deployment_v1" "logstash" {
  metadata {
    name      = "logstash"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
    labels    = { app = "logstash" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "logstash" }
    }
    template {
      metadata {
        labels = { app = "logstash" }
      }
      spec {
        container {
          name  = "logstash"
          image = "docker.elastic.co/logstash/logstash:8.5.1"

          port {
            container_port = 9601
            name           = "http"
          }

          volume_mount {
            name       = "config"
            mount_path = "/usr/share/logstash/config/logstash.yml"
            sub_path   = "logstash.yml"
          }

          volume_mount {
            name       = "config"
            mount_path = "/usr/share/logstash/config/pipelines.yml"
            sub_path   = "pipelines.yml"
          }

          volume_mount {
            name       = "pipeline"
            mount_path = "/usr/share/logstash/pipeline/teleport-audit.conf"
            sub_path   = "teleport-audit.conf"
          }

          volume_mount {
            name       = "tls"
            mount_path = "/usr/share/logstash/tls"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "512Mi"
            }
            limits = {
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.logstash_config.metadata[0].name
          }
        }

        volume {
          name = "pipeline"
          config_map {
            name = kubernetes_config_map.logstash_pipeline.metadata[0].name
          }
        }

        volume {
          name = "tls"
          secret {
            secret_name = kubernetes_secret.logstash_tls.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [helm_release.elasticsearch]
}

resource "kubernetes_service_v1" "logstash" {
  metadata {
    name      = "logstash"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
    labels    = { app = "logstash" }
  }
  spec {
    selector = { app = "logstash" }
    port {
      port        = 9601
      target_port = 9601
      name        = "http"
    }
  }
}

# ---------------------------------------------------------------------------- #
# Teleport CRDs — manually created because the Helm chart's crd.create cannot
# create resources cross-namespace (chart runs in psh-elasticsearch, but the
# Teleport operator watches psh-cluster).
# ---------------------------------------------------------------------------- #

# Role granting access to read audit events — required by the event handler bot
resource "kubectl_manifest" "teleport_role_event_handler" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "event-handler"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        rules = [
          {
            resources = ["event", "session"]
            verbs     = ["list", "read"]
          }
        ]
      }
    }
  })
}

# Provision token — kubernetes join method so tbot authenticates via its
# service account JWT without needing a static secret
resource "kubectl_manifest" "teleport_event_handler_token" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportProvisionToken"
    metadata = {
      name      = "event-handler-bot"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles       = ["Bot"]
      bot_name    = "event-handler"
      join_method = "kubernetes"
      kubernetes = {
        type = "in_cluster"
        allow = [
          {
            service_account = "psh-elasticsearch:teleport-event-handler-tbot"
          }
        ]
      }
    }
  })

  depends_on = [helm_release.teleport_cluster]
}

# Bot identity — references the role and is matched by the provision token's bot_name
resource "kubectl_manifest" "teleport_bot_event_handler" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportBotV1"
    metadata = {
      name      = "event-handler"
      namespace = helm_release.teleport_cluster.namespace
    }
    spec = {
      roles = ["event-handler"]
    }
  })

  depends_on = [
    kubectl_manifest.teleport_role_event_handler,
  ]
}

# ---------------------------------------------------------------------------- #
# Teleport Event Handler Helm Chart
#
# Uses Machine ID (tbot sidecar) with Kubernetes join method. CRDs are created
# manually above since the chart can't create them cross-namespace.
# ---------------------------------------------------------------------------- #

resource "helm_release" "teleport_event_handler" {
  name       = "teleport-event-handler"
  namespace  = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-plugin-event-handler"
  version    = var.teleport_version

  wait    = false
  timeout = 300

  values = [<<EOF
teleport:
  address: "${local.teleport_cluster_fqdn}:443"
fluentd:
  url: "https://logstash.psh-elasticsearch.svc.cluster.local:9601/events"
  sessionUrl: "https://logstash.psh-elasticsearch.svc.cluster.local:9601/sessions"
  certificate:
    secretName: "${kubernetes_secret.event_handler_client_tls.metadata[0].name}"
    caPath: "ca.crt"
    certPath: "client.crt"
    keyPath: "client.key"
eventHandler:
  storagePath: "/var/lib/teleport/plugins/event-handler/storage"
  timeout: "10s"
  batch: 20
  windowSize: "24h"
# Use an emptyDir for the plugin's checkpoint storage instead of the
# chart's built-in EBS PVC. The chart's PVC is RWO + WaitForFirstConsumer,
# so the PV gets pinned to whichever AZ schedules the first consumer. EKS
# node-group churn (blue/green rolls) routinely removes nodes from that AZ,
# leaving the Recreate-strategy pod unschedulable on every Helm upgrade.
# The plugin's checkpoint is ~1 KiB of cursor state; on restart it resumes
# from "now", losing only events from the restart window. Acceptable for
# this demo cluster.
#
# Note: a volume MUST be mounted at storagePath because the parent
# /var/lib/teleport/plugins/event-handler is occupied by the (read-only)
# fluentd-certificate secret mount; without an overlay there, mkdir fails.
persistentVolumeClaim:
  enabled: false
volumes:
  - name: storage
    emptyDir: {}
volumeMounts:
  - name: storage
    mountPath: "/var/lib/teleport/plugins/event-handler/storage"
tbot:
  enabled: true
  clusterName: "${local.teleport_cluster_fqdn}"
  teleportProxyAddress: "${local.teleport_cluster_fqdn}:443"
  token: "event-handler-bot"
  joinMethod: "kubernetes"
  crd:
    create: false
EOF
  ]

  depends_on = [
    helm_release.teleport_cluster,
    kubernetes_deployment_v1.logstash,
    kubernetes_service_v1.logstash,
    kubernetes_job.event_handler_es_seed,
    kubectl_manifest.teleport_bot_event_handler,
    kubectl_manifest.teleport_event_handler_token,
  ]
}
