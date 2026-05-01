resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace_v1.apps.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.29.0"

  wait = true

  depends_on = [helm_release.prometheus]

  values = [<<EOF
deploymentMode: SingleBinary
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h
  limits_config:
    retention_period: 168h
  # Compactor must be told to enforce the retention_period above; without
  # retention_enabled the limits_config setting is a no-op and the PVC grows
  # forever. delete_request_store is required when retention_enabled=true.
  compactor:
    working_directory: /var/loki/compactor
    retention_enabled: true
    delete_request_store: filesystem
singleBinary:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 512Mi
  persistence:
    enabled: true
    size: 20Gi
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0
gateway:
  enabled: false
monitoring:
  selfMonitoring:
    enabled: false
    grafanaAgent:
      installOperator: false
  lokiCanary:
    enabled: false
lokiCanary:
  enabled: false
test:
  enabled: false
chunksCache:
  enabled: false
resultsCache:
  enabled: false
EOF
  ]
}

resource "helm_release" "promtail" {
  name       = "promtail"
  namespace  = kubernetes_namespace_v1.apps.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.16.6"

  wait = true

  depends_on = [helm_release.loki]

  values = [<<EOF
config:
  clients:
    - url: http://loki.psh-apps.svc.cluster.local:3100/loki/api/v1/push
  snippets:
    pipelineStages:
      - cri: {}
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    memory: 128Mi
tolerations:
  - operator: Exists
    effect: NoSchedule
EOF
  ]
}
