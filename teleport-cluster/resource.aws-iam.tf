# https://goteleport.com/docs/enroll-resources/application-access/cloud-apis/aws-console/

resource "aws_iam_role" "irsa_aws_console" {
  name = "${local.teleport_cluster_name}-irsa-aws-console"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.oidc.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com",
          "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${kubernetes_namespace_v1.teleport_cluster.metadata[0].name}:${local.teleport_agent_name}"
        }
      }
    }]
  })
}

# ---------------------------------------------------------------------------- #
# Read Only Role
# ---------------------------------------------------------------------------- #
resource "aws_iam_role_policy_attachment" "irsa_aws_console_ro_policy" {
  role       = aws_iam_role.irsa_aws_console.name
  policy_arn = aws_iam_policy.irsa_aws_console_sts_ro.arn
}

resource "aws_iam_policy" "irsa_aws_console_sts_ro" {
  name = "${local.teleport_cluster_name}-aws-console-sts-ro"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.irsa_aws_console_ro.arn
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "irsa_aws_console_ro" {
  role       = aws_iam_role.irsa_aws_console_ro.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role" "irsa_aws_console_ro" {
  name = "${var.resource_prefix}aws-ro"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = aws_iam_role.irsa_aws_console.arn
        }
      },
    ]
  })
}
# ---------------------------------------------------------------------------- #
# Admin Role
# ---------------------------------------------------------------------------- #
resource "aws_iam_role" "irsa_aws_console_admin" {
  name = "${var.resource_prefix}aws-admin"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = aws_iam_role.irsa_aws_console.arn
        }
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "irsa_aws_console_admin" {
  role       = aws_iam_role.irsa_aws_console_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_policy" "irsa_aws_console_sts_admin" {
  name = "${local.teleport_cluster_name}-aws-console-sts-admin"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.irsa_aws_console_admin.arn
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "irsa_aws_console_admin_policy" {
  role       = aws_iam_role.irsa_aws_console.name
  policy_arn = aws_iam_policy.irsa_aws_console_sts_admin.arn
}

# ---------------------------------------------------------------------------- #
# Bedrock Read Only Role
# ---------------------------------------------------------------------------- #
resource "aws_iam_role" "irsa_aws_console_bedrock_ro" {
  name = "${var.resource_prefix}aws-bedrock-ro"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = aws_iam_role.irsa_aws_console.arn
        }
      },
    ]
  })
}

resource "aws_iam_policy" "irsa_aws_console_bedrock_ro" {
  name = "${local.teleport_cluster_name}-aws-console-bedrock-ro"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:List*",
          "bedrock:Get*",
          "sagemaker:List*",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "irsa_aws_console_bedrock_ro" {
  role       = aws_iam_role.irsa_aws_console_bedrock_ro.name
  policy_arn = aws_iam_policy.irsa_aws_console_bedrock_ro.arn
}

resource "aws_iam_policy" "irsa_aws_console_sts_bedrock_ro" {
  name = "${local.teleport_cluster_name}-aws-console-sts-bedrock-ro"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.irsa_aws_console_bedrock_ro.arn
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "irsa_aws_console_bedrock_ro_policy" {
  role       = aws_iam_role.irsa_aws_console.name
  policy_arn = aws_iam_policy.irsa_aws_console_sts_bedrock_ro.arn
}

# ---------------------------------------------------------------------------- #
# Teleport Role
# ---------------------------------------------------------------------------- #
resource "kubectl_manifest" "teleport_role_aws_console" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}aws-console"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        app_labels = {
          app = "aws"
        }
        aws_role_arns = [
          aws_iam_role.irsa_aws_console_ro.arn,
          aws_iam_role.irsa_aws_console_admin.arn,
        ]
      }
    }
  })
}

resource "kubectl_manifest" "teleport_role_aws_bedrock_ro" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}aws-bedrock-ro"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        app_labels = {
          app = "aws"
        }
        aws_role_arns = [
          aws_iam_role.irsa_aws_console_bedrock_ro.arn,
        ]
      }
    }
  })
}