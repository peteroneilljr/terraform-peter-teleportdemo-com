# https://goteleport.com/docs/admin-guides/deploy-a-cluster/helm-deployments/aws/

resource "kubernetes_namespace_v1" "teleport_cluster" {
  metadata {
    name = "${var.resource_prefix}cluster"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}
data "local_sensitive_file" "license" {
  filename = var.teleport_license_filepath
}
resource "kubernetes_secret" "license" {
  metadata {
    name      = "license"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }

  data = {
    "license.pem" = data.local_sensitive_file.license.content
  }

  type = "Opaque"
}


resource "helm_release" "teleport_cluster" {
  name       = local.teleport_cluster_name
  namespace  = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-cluster"
  version    = var.teleport_version


  wait    = true # deployment will take longer than 10 minutes on first run
  timeout = 900

  values = [<<EOF
    enterprise: true
    licenseSecretName: ${kubernetes_secret.license.metadata[0].name}
    clusterName: ${local.teleport_cluster_fqdn}
    publicAddr: 
      - "${local.teleport_cluster_fqdn}:443"
    authentication:
      type: github
      connectorName: github
    proxyListenerMode: multiplex
    operator:
      enabled: true
      installCRDs: ${var.teleport_install_CRDs}
    serviceAccount:
      create: true
      name: ${local.teleport_cluster_name}
    annotations:
      service:
        service.beta.kubernetes.io/aws-load-balancer-name: ${local.teleport_cluster_name}
      serviceAccount:
        "eks.amazonaws.com/role-arn": "${aws_iam_role.irsa_role.arn}"
    chartMode: aws
    aws:
      region: ${var.aws_region}      
      backendTable: ${aws_dynamodb_table.teleport_backend.name} 
      auditLogTable: ${aws_dynamodb_table.teleport_events.name}
      auditLogMirrorOnStdout: false
      sessionRecordingBucket: ${aws_s3_bucket.teleport_sessions.bucket}
      backups: true 
      dynamoAutoScaling: false
    highAvailability:
      replicaCount: 2
      certManager:
        enabled: true
        addPublicAddrs: true
        issuerKind: ClusterIssuer
        issuerName: letsencrypt-prod              
    # If you are running Kubernetes 1.23 or above, disable PodSecurityPolicies
    podSecurityPolicy:
      enabled: false 
    EOF
  ]

  depends_on = [
    aws_iam_role_policy_attachment.irsa_attach_dynamodb,
    aws_iam_role_policy_attachment.irsa_attach_s3,
    helm_release.teleport_crds,
  ]
}
# ---------------------------------------------------------------------------- #
# Teleport Role
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "teleport_role_k8s" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      name       = "${var.resource_prefix}k8s"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        kubernetes_groups = ["system:masters"]
        kubernetes_labels = {
          "*" = "*"
        }
        kubernetes_resources = [
          {
            kind      = "*"
            name      = "*"
            namespace = "*"
            verbs     = ["*"]
          }
        ]
      }
    }
  })
}
