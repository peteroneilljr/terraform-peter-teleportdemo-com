resource "random_string" "teleport_agent" {
  length  = 32
  special = false
  upper   = false
  lower   = true
}

resource "kubectl_manifest" "teleport_agent" {
  yaml_body = yamlencode(
    {
      apiVersion = "resources.teleport.dev/v2"
      kind       = "TeleportProvisionToken"

      metadata = {
        name      = random_string.teleport_agent.result
        namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
      }

      spec = {
        roles       = ["App", "Db"]
        join_method = "token"

      }
    }
  )

  depends_on = [
    helm_release.teleport_cluster
  ]
}

locals {
  teleport_agent_name = "psh-teleport-agent"
}


resource "helm_release" "teleport_agent" {
  name       = local.teleport_agent_name
  namespace  = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-kube-agent"
  version    = var.teleport_version

  set = [
    {
      name  = "authToken"
      value = random_string.teleport_agent.result
    }
  ]

  wait = false

  values = [<<EOF
roles: app,db
proxyAddr: ${local.teleport_cluster_fqdn}:443
enterprise: true
annotations:
  serviceAccount:
    "eks.amazonaws.com/role-arn": "${aws_iam_role.irsa_aws_console.arn}"
highAvailability:
    replicaCount: 2
    podDisruptionBudget:
        enabled: true
        minAvailable: 1
appResources:
  - labels:
      "*": "*"
databaseResources:
  - labels:
      "*": "*"
EOF
  ]
}
