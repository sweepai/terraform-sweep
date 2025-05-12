# IAM policy for Bedrock access
resource "aws_iam_policy" "bedrock_invoke_models_policy" {
  name        = "bedrock-invoke-models-policy-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  description = "Policy to allow invoking Bedrock models"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VisualEditor0"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for EC2 instances
resource "aws_iam_role" "bedrock_invoke_models_role" {
  name = "bedrock-invoke-models-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "bedrock_policy_attachment" {
  role       = aws_iam_role.bedrock_invoke_models_role.name
  policy_arn = aws_iam_policy.bedrock_invoke_models_policy.arn
}

# Instance profile for EC2
resource "aws_iam_instance_profile" "backend_instance_profile" {
  name = "backend-instance-profile-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  role = aws_iam_role.bedrock_invoke_models_role.name
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.backend_instance_profile.name
}

output "instance_profile_arn" {
  value = aws_iam_instance_profile.backend_instance_profile.arn
}