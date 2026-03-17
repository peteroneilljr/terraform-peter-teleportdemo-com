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
      version       = 2
      refresh       = "30s"
      time = {
        from = "now-1h"
        to   = "now"
      }
      timepicker = {}
      templating = { list = [] }
      panels = concat(
        # ── Row 1: Backend Performance ──
        [
          {
            id        = 102
            type      = "row"
            title     = "Backend Performance"
            gridPos   = { x = 0, y = 0, w = 24, h = 1 }
            collapsed = false
            panels    = []
          },
          {
            id      = 8
            type    = "timeseries"
            title   = "Backend Read/Write Rate"
            gridPos = { x = 0, y = 1, w = 12, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "rate(teleport_backend_reads_total[5m])"
                legendFormat = "reads"
                refId        = "A"
              },
              {
                expr         = "rate(teleport_backend_writes_total[5m])"
                legendFormat = "writes"
                refId        = "B"
              }
            ]
            options = {
              tooltip = { mode = "multi" }
              legend  = { displayMode = "list", placement = "bottom" }
            }
            fieldConfig = {
              defaults = {
                unit   = "ops"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
          {
            id      = 9
            type    = "timeseries"
            title   = "Backend Latency (p50/p95/p99)"
            gridPos = { x = 12, y = 1, w = 12, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "histogram_quantile(0.5, rate(backend_read_seconds_bucket[5m]))"
                legendFormat = "read p50"
                refId        = "A"
              },
              {
                expr         = "histogram_quantile(0.95, rate(backend_read_seconds_bucket[5m]))"
                legendFormat = "read p95"
                refId        = "B"
              },
              {
                expr         = "histogram_quantile(0.99, rate(backend_read_seconds_bucket[5m]))"
                legendFormat = "read p99"
                refId        = "C"
              },
              {
                expr         = "histogram_quantile(0.5, rate(backend_write_seconds_bucket[5m]))"
                legendFormat = "write p50"
                refId        = "D"
              },
              {
                expr         = "histogram_quantile(0.95, rate(backend_write_seconds_bucket[5m]))"
                legendFormat = "write p95"
                refId        = "E"
              },
              {
                expr         = "histogram_quantile(0.99, rate(backend_write_seconds_bucket[5m]))"
                legendFormat = "write p99"
                refId        = "F"
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
          },
        ],

        # ── Row 2: Audit & Security ──
        [
          {
            id        = 103
            type      = "row"
            title     = "Audit & Security"
            gridPos   = { x = 0, y = 7, w = 24, h = 1 }
            collapsed = false
            panels    = []
          },
          {
            id      = 10
            type    = "timeseries"
            title   = "Audit Events"
            gridPos = { x = 0, y = 8, w = 8, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "rate(teleport_audit_emit_events[5m])"
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
                unit   = "ops"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
          {
            id      = 11
            type    = "timeseries"
            title   = "Failed Logins & Cert Mismatches"
            gridPos = { x = 8, y = 8, w = 8, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "rate(failed_login_attempts_total[5m])"
                legendFormat = "failed logins"
                refId        = "A"
              },
              {
                expr         = "rate(certificate_mismatch_total[5m])"
                legendFormat = "cert mismatches"
                refId        = "B"
              }
            ]
            options = {
              tooltip = { mode = "multi" }
              legend  = { displayMode = "list", placement = "bottom" }
            }
            fieldConfig = {
              defaults = {
                unit   = "ops"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
          {
            id      = 12
            type    = "timeseries"
            title   = "Certificate Generation Rate"
            gridPos = { x = 16, y = 8, w = 8, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "rate(auth_generate_requests_total[5m])"
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
                unit   = "ops"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
        ],

        # ── Row 3: gRPC ──
        [
          {
            id        = 104
            type      = "row"
            title     = "gRPC"
            gridPos   = { x = 0, y = 14, w = 24, h = 1 }
            collapsed = false
            panels    = []
          },
          {
            id      = 13
            type    = "timeseries"
            title   = "gRPC Request Rate (Top 10)"
            gridPos = { x = 0, y = 15, w = 12, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "topk(10, sum(rate(grpc_server_handled_total[5m])) by (grpc_method))"
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
                unit   = "ops"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
          {
            id      = 14
            type    = "timeseries"
            title   = "gRPC Error Rate"
            gridPos = { x = 12, y = 15, w = 12, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "sum(rate(grpc_server_handled_total{grpc_code!=\"OK\"}[5m])) by (grpc_code)"
                legendFormat = "{{grpc_code}}"
                refId        = "A"
              }
            ]
            options = {
              tooltip = { mode = "multi" }
              legend  = { displayMode = "list", placement = "bottom" }
            }
            fieldConfig = {
              defaults = {
                unit   = "ops"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
        ],

        # ── Row 4: Go Runtime ──
        [
          {
            id        = 105
            type      = "row"
            title     = "Go Runtime"
            gridPos   = { x = 0, y = 21, w = 24, h = 1 }
            collapsed = false
            panels    = []
          },
          {
            id      = 15
            type    = "timeseries"
            title   = "Goroutines"
            gridPos = { x = 0, y = 22, w = 8, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "go_goroutines{job=\"teleport-cluster\"}"
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
                unit   = "short"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
          {
            id      = 16
            type    = "timeseries"
            title   = "Memory Usage"
            gridPos = { x = 8, y = 22, w = 8, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "process_resident_memory_bytes{job=\"teleport-cluster\"}"
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
                unit   = "bytes"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
          {
            id      = 17
            type    = "timeseries"
            title   = "CPU Usage"
            gridPos = { x = 16, y = 22, w = 8, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "rate(process_cpu_seconds_total{job=\"teleport-cluster\"}[5m])"
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
                unit   = "percentunit"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
        ],

        # ── Row 5: Cluster Health ──
        [
          {
            id        = 100
            type      = "row"
            title     = "Cluster Health"
            gridPos   = { x = 0, y = 28, w = 24, h = 1 }
            collapsed = false
            panels    = []
          },
          {
            id      = 1
            type    = "stat"
            title   = "Process State"
            gridPos = { x = 0, y = 29, w = 6, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "process_state"
                legendFormat = "{{instance}}"
                refId        = "A"
              }
            ]
            options = {
              reduceOptions = { calcs = ["lastNotNull"] }
              colorMode     = "background"
              graphMode     = "none"
              orientation   = "horizontal"
            }
            fieldConfig = {
              defaults = {
                thresholds = {
                  mode = "absolute"
                  steps = [
                    { color = "green", value = null },
                    { color = "yellow", value = 1 },
                    { color = "red", value = 2 }
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
            title   = "Build Info"
            gridPos = { x = 6, y = 29, w = 6, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "teleport_build_info"
                legendFormat = "{{version}}"
                refId        = "A"
              }
            ]
            options = {
              reduceOptions = { calcs = ["lastNotNull"], fields = "/^version$/" }
              colorMode     = "none"
              graphMode     = "none"
              textMode      = "name"
              orientation   = "horizontal"
            }
            fieldConfig = {
              defaults = {
                color = { mode = "fixed", fixedColor = "text" }
              }
              overrides = []
            }
          },
          {
            id      = 3
            type    = "stat"
            title   = "Registered Servers"
            gridPos = { x = 12, y = 29, w = 6, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "teleport_registered_servers"
                legendFormat = "{{type}}"
                refId        = "A"
              }
            ]
            options = {
              reduceOptions = { calcs = ["lastNotNull"] }
              colorMode     = "value"
              graphMode     = "none"
              orientation   = "horizontal"
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
            type    = "stat"
            title   = "Total Roles"
            gridPos = { x = 18, y = 29, w = 6, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "teleport_roles_total"
                legendFormat = ""
                refId        = "A"
              }
            ]
            options = {
              reduceOptions = { calcs = ["lastNotNull"] }
              colorMode     = "value"
              graphMode     = "none"
              orientation   = "horizontal"
            }
            fieldConfig = {
              defaults = {
                unit  = "short"
                color = { mode = "fixed", fixedColor = "blue" }
              }
              overrides = []
            }
          },
        ],

        # ── Row 6: Resources & Connections ──
        [
          {
            id        = 101
            type      = "row"
            title     = "Resources & Connections"
            gridPos   = { x = 0, y = 35, w = 24, h = 1 }
            collapsed = false
            panels    = []
          },
          {
            id      = 5
            type    = "stat"
            title   = "Connected Resources"
            gridPos = { x = 0, y = 36, w = 8, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "sum(teleport_connected_resources) by (type)"
                legendFormat = "{{type}}"
                refId        = "A"
              }
            ]
            options = {
              reduceOptions = { calcs = ["lastNotNull"] }
              colorMode     = "value"
              graphMode     = "none"
              orientation   = "horizontal"
            }
            fieldConfig = {
              defaults = {
                color = { mode = "palette-classic" }
              }
              overrides = []
            }
          },
          {
            id      = 6
            type    = "stat"
            title   = "Reverse Tunnels"
            gridPos = { x = 8, y = 36, w = 8, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "teleport_reverse_tunnels_connected"
                legendFormat = "{{instance}}"
                refId        = "A"
              }
            ]
            options = {
              reduceOptions = { calcs = ["lastNotNull"] }
              colorMode     = "value"
              graphMode     = "none"
              orientation   = "horizontal"
            }
            fieldConfig = {
              defaults = {
                unit  = "short"
                color = { mode = "fixed", fixedColor = "purple" }
              }
              overrides = []
            }
          },
          {
            id      = 7
            type    = "timeseries"
            title   = "Active Sessions"
            gridPos = { x = 16, y = 36, w = 8, h = 6 }
            datasource = {
              type = "prometheus"
              uid  = "prometheus"
            }
            targets = [
              {
                expr         = "server_interactive_sessions_total"
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
                unit   = "short"
                color  = { mode = "palette-classic" }
                custom = { lineWidth = 1, fillOpacity = 10 }
              }
              overrides = []
            }
          },
        ],
      )
    })
  }
}
