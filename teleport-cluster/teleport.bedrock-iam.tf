resource "aws_iam_policy" "teleport_bedrock_invoke" {
  name = "${local.teleport_cluster_name}-bedrock-invoke"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBedrockInvokeModel"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:us-west-2:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-sonnet-4-6",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-6",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "irsa_attach_bedrock" {
  role       = aws_iam_role.irsa_role.name
  policy_arn = aws_iam_policy.teleport_bedrock_invoke.arn
}
