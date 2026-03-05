data "aws_eks_cluster" "cluster" {
  name = var.aws_eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.aws_eks_cluster_name
}

data "aws_iam_openid_connect_provider" "oidc" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

data "aws_region" "current" {}

data "aws_route53_zone" "main" {
  name = var.aws_domain_name
}

data "http" "teleport_db_ca" {
  url = "https://${aws_route53_record.cluster_endpoint.fqdn}/webapi/auth/export?type=db-client"

  request_timeout_ms = 10000

  retry {
    attempts     = 30
    min_delay_ms = 10000
  }

  depends_on = [
    aws_iam_role_policy_attachment.irsa_attach_dynamodb,
    helm_release.teleport_cluster
  ]
}
