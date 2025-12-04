# IRSA Module for Harbor
# Creates IAM role with trust policy for specific service account and permissions policy for S3/KMS access

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# IAM Role for Harbor Service Account
resource "aws_iam_role" "harbor_s3" {
  name        = var.role_name
  description = "IAM role for Harbor registry to access S3 via IRSA"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_id}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_provider_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.common_tags
}

# IAM Policy for S3 Access
resource "aws_iam_policy" "harbor_s3_access" {
  name        = "${var.role_name}-s3-policy"
  description = "Least privilege policy for Harbor to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HarborS3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = var.s3_bucket_arn
      },
      {
        Sid    = "HarborS3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${var.s3_bucket_arn}/*"
      }
    ]
  })

  tags = var.common_tags
}

# IAM Policy for KMS Access
resource "aws_iam_policy" "harbor_kms_access" {
  name        = "${var.role_name}-kms-policy"
  description = "Policy for Harbor to use KMS key for S3 encryption"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "HarborKMSAccess"
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      Resource = var.kms_key_arn
      Condition = {
        StringEquals = {
          "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
        }
      }
    }]
  })

  tags = var.common_tags
}

# Attach S3 policy to role
resource "aws_iam_role_policy_attachment" "harbor_s3" {
  role       = aws_iam_role.harbor_s3.name
  policy_arn = aws_iam_policy.harbor_s3_access.arn
}

# Attach KMS policy to role
resource "aws_iam_role_policy_attachment" "harbor_kms" {
  role       = aws_iam_role.harbor_s3.name
  policy_arn = aws_iam_policy.harbor_kms_access.arn
}
