# https://goteleport.com/docs/admin-guides/deploy-a-cluster/helm-deployments/aws/

resource "kubernetes_namespace_v1" "teleport_cluster" {
  metadata {
    name = "psh-cluster"
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


  wait    = false
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
    # Mount the ArgoCD SAML SP definition (from kubernetes_config_map.argocd_saml_sp) into
    # auth pods at /etc/teleport-sp/saml-sp.yaml. This is required because the auth
    # container is distroless — there's no shell or writable filesystem to stage files.
    # After the mount is in place, run `tctl create -f /etc/teleport-sp/saml-sp.yaml`
    # from inside an auth pod to register the SP in Teleport's backend.
    # See resource.argocd.tf for the full SAML login flow and why tctl is needed.
    auth:
      teleportConfig:
        access_graph:
          enabled: true
          endpoint: teleport-access-graph.psh-teleport-access-graph.svc.cluster.local:443
          ca: /var/run/access-graph/ca.pem
      extraVolumes:
        - name: argocd-saml-sp
          configMap:
            name: ${kubernetes_config_map.argocd_saml_sp.metadata[0].name}
        - name: tag-ca
          configMap:
            name: ${kubernetes_config_map.tag_ca.metadata[0].name}
      extraVolumeMounts:
        - name: argocd-saml-sp
          mountPath: /etc/teleport-sp
          readOnly: true
        - name: tag-ca
          mountPath: /var/run/access-graph
          readOnly: true
    podSecurityPolicy:
      enabled: false
    EOF
  ]

  depends_on = [
    aws_iam_role_policy_attachment.irsa_attach_dynamodb,
    aws_iam_role_policy_attachment.irsa_attach_s3,
    aws_iam_role_policy_attachment.irsa_attach_bedrock,
    helm_release.teleport_crds,
    kubernetes_config_map.tag_ca,
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
