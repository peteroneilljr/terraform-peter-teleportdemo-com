resource "helm_release" "prometheus" {
  name       = "prometheus"
  namespace  = kubernetes_namespace_v1.apps.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"

  wait = true

  values = [<<EOF
alertmanager:
  enabled: false
kube-state-metrics:
  enabled: false
prometheus-node-exporter:
  enabled: false
prometheus-pushgateway:
  enabled: false
server:
  retention: "7d"
  persistentVolume:
    enabled: true
    size: 10Gi
serverFiles:
  prometheus.yml:
    scrape_configs:
      - job_name: teleport-cluster
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: [psh-cluster]
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
            regex: teleport-cluster
            action: keep
          - source_labels: [__meta_kubernetes_pod_ip]
            action: replace
            target_label: __address__
            replacement: "$1:3000"
      - job_name: teleport-agent
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: [psh-cluster]
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
            regex: teleport-kube-agent
            action: keep
          - source_labels: [__meta_kubernetes_pod_ip]
            action: replace
            target_label: __address__
            replacement: "$1:3000"
EOF
  ]
}
