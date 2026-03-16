resource "kubernetes_config_map_v1" "grafana_dashboard_teleport" {
  metadata {
    name      = "grafana-dashboard-teleport"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "teleport-overview.json" = jsonencode({
      title         = "Teleport Overview"
      uid           = "teleport-overview"
      schemaVersion = 38
      version       = 1
      refresh       = "30s"
      time = {
        from = "now-1h"
        to   = "now"
      }
      timepicker = {}
      templating = {
        list = [
          {
            name  = "DS_PROMETHEUS"
            label = "Prometheus"
            type  = "datasource"
            query = "prometheus"
          }
        ]
      }
      panels = [
        # Row 1: Cluster Health
        {
          id      = 1
          type    = "stat"
          title   = "Process State"
          gridPos = { x = 0, y = 0, w = 12, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "teleport_process_state"
              legendFormat = "{{instance}}"
              refId        = "A"
            }
          ]
          options = {
            reduceOptions = {
              calcs = ["lastNotNull"]
            }
            colorMode   = "background"
            graphMode   = "none"
            orientation = "horizontal"
          }
          fieldConfig = {
            defaults = {
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "red", value = null },
                  { color = "green", value = 1 }
                ]
              }
              color = { mode = "thresholds" }
            }
            overrides = []
          }
        },
        {
          id      = 2
          type    = "stat"
          title   = "Registered Servers"
          gridPos = { x = 12, y = 0, w = 12, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "teleport_registered_servers"
              legendFormat = "{{type}}"
              refId        = "A"
            }
          ]
          options = {
            reduceOptions = {
              calcs = ["lastNotNull"]
            }
            colorMode   = "value"
            graphMode   = "none"
            orientation = "horizontal"
          }
          fieldConfig = {
            defaults = {
              color = { mode = "palette-classic" }
            }
            overrides = []
          }
        },
        # Row 2: Active Sessions & Connections
        {
          id      = 3
          type    = "stat"
          title   = "Connected Resources"
          gridPos = { x = 0, y = 8, w = 12, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "teleport_connected_resources"
              legendFormat = "{{type}}"
              refId        = "A"
            }
          ]
          options = {
            reduceOptions = {
              calcs = ["lastNotNull"]
            }
            colorMode   = "value"
            graphMode   = "none"
            orientation = "horizontal"
          }
          fieldConfig = {
            defaults = {
              color = { mode = "palette-classic" }
            }
            overrides = []
          }
        },
        {
          id      = 4
          type    = "timeseries"
          title   = "Interactive Sessions Rate"
          gridPos = { x = 12, y = 8, w = 12, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "rate(teleport_server_interactive_sessions_total[5m])"
              legendFormat = "{{instance}}"
              refId        = "A"
            }
          ]
          options = {
            tooltip = { mode = "multi" }
            legend  = { displayMode = "list", placement = "bottom" }
          }
          fieldConfig = {
            defaults = {
              color  = { mode = "palette-classic" }
              custom = { lineWidth = 1, fillOpacity = 10 }
            }
            overrides = []
          }
        },
        # Row 3: Backend Performance
        {
          id      = 5
          type    = "timeseries"
          title   = "Backend Request Rate"
          gridPos = { x = 0, y = 16, w = 12, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "rate(teleport_backend_requests_total[5m])"
              legendFormat = "{{operation}}"
              refId        = "A"
            }
          ]
          options = {
            tooltip = { mode = "multi" }
            legend  = { displayMode = "list", placement = "bottom" }
          }
          fieldConfig = {
            defaults = {
              color  = { mode = "palette-classic" }
              custom = { lineWidth = 1, fillOpacity = 10 }
            }
            overrides = []
          }
        },
        {
          id      = 6
          type    = "timeseries"
          title   = "Backend Latency"
          gridPos = { x = 12, y = 16, w = 12, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "rate(teleport_backend_read_seconds_bucket[5m])"
              legendFormat = "read {{le}}"
              refId        = "A"
            },
            {
              expr         = "rate(teleport_backend_write_seconds_bucket[5m])"
              legendFormat = "write {{le}}"
              refId        = "B"
            }
          ]
          options = {
            tooltip = { mode = "multi" }
            legend  = { displayMode = "list", placement = "bottom" }
          }
          fieldConfig = {
            defaults = {
              color  = { mode = "palette-classic" }
              custom = { lineWidth = 1, fillOpacity = 10 }
            }
            overrides = []
          }
        },
        # Row 4: Audit & Certificates
        {
          id      = 7
          type    = "timeseries"
          title   = "Audit Event Rate"
          gridPos = { x = 0, y = 24, w = 8, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "rate(teleport_audit_emit_events_total[5m])"
              legendFormat = "{{type}}"
              refId        = "A"
            }
          ]
          options = {
            tooltip = { mode = "multi" }
            legend  = { displayMode = "list", placement = "bottom" }
          }
          fieldConfig = {
            defaults = {
              color  = { mode = "palette-classic" }
              custom = { lineWidth = 1, fillOpacity = 10 }
            }
            overrides = []
          }
        },
        {
          id      = 8
          type    = "timeseries"
          title   = "Certificate Generation Rate"
          gridPos = { x = 8, y = 24, w = 8, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "rate(teleport_generate_requests_total[5m])"
              legendFormat = "{{instance}}"
              refId        = "A"
            }
          ]
          options = {
            tooltip = { mode = "multi" }
            legend  = { displayMode = "list", placement = "bottom" }
          }
          fieldConfig = {
            defaults = {
              color  = { mode = "palette-classic" }
              custom = { lineWidth = 1, fillOpacity = 10 }
            }
            overrides = []
          }
        },
        {
          id      = 9
          type    = "stat"
          title   = "Certificate Mismatches"
          gridPos = { x = 16, y = 24, w = 8, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "teleport_certificate_mismatch_total"
              legendFormat = "{{instance}}"
              refId        = "A"
            }
          ]
          options = {
            reduceOptions = {
              calcs = ["lastNotNull"]
            }
            colorMode   = "background"
            graphMode   = "none"
            orientation = "horizontal"
          }
          fieldConfig = {
            defaults = {
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "green", value = null },
                  { color = "red", value = 1 }
                ]
              }
              color = { mode = "thresholds" }
            }
            overrides = []
          }
        },
        # Row 5: gRPC
        {
          id      = 10
          type    = "timeseries"
          title   = "gRPC Request Rate (Top 10)"
          gridPos = { x = 0, y = 32, w = 12, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "topk(10, rate(grpc_server_handled_total[5m]))"
              legendFormat = "{{grpc_method}}"
              refId        = "A"
            }
          ]
          options = {
            tooltip = { mode = "multi" }
            legend  = { displayMode = "list", placement = "bottom" }
          }
          fieldConfig = {
            defaults = {
              color  = { mode = "palette-classic" }
              custom = { lineWidth = 1, fillOpacity = 10 }
            }
            overrides = []
          }
        },
        {
          id      = 11
          type    = "timeseries"
          title   = "gRPC p99 Latency"
          gridPos = { x = 12, y = 32, w = 12, h = 8 }
          datasource = {
            type = "prometheus"
            uid  = "$${DS_PROMETHEUS}"
          }
          targets = [
            {
              expr         = "histogram_quantile(0.99, rate(grpc_server_handling_seconds_bucket[5m]))"
              legendFormat = "{{grpc_method}}"
              refId        = "A"
            }
          ]
          options = {
            tooltip = { mode = "multi" }
            legend  = { displayMode = "list", placement = "bottom" }
          }
          fieldConfig = {
            defaults = {
              unit   = "s"
              color  = { mode = "palette-classic" }
              custom = { lineWidth = 1, fillOpacity = 10 }
            }
            overrides = []
          }
        }
      ]
    })
  }
}
