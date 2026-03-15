resource "kubernetes_namespace_v1" "apps" {
  metadata {
    name = "psh-apps"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  namespace  = kubernetes_namespace_v1.apps.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "9.2.6"

  wait = true

  values = [<<EOF
  rbac:
    namespaced: true
  grafana.ini:
    auth.jwt:
        enabled: true
        header_name: Teleport-Jwt-Assertion
        username_claim: sub
        email_claim: sub 
        auto_sign_up: true
        jwk_set_url: https://${local.teleport_cluster_fqdn}/.well-known/jwks.json
        username_attribute_path: username
        role_attribute_path: contains(roles[*], 'access') && 'Admin' || contains(roles[*], 'editor') && 'Editor' || 'Viewer'
        allow_assign_grafana_admin: true
        cache_ttl: 60m
  EOF
  ]
}