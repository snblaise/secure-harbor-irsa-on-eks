# Outputs for IRSA Module

output "role_arn" {
  description = "ARN of the IAM role for Harbor IRSA"
  value       = aws_iam_role.harbor_s3.arn
}

output "role_name" {
  description = "Name of the IAM role for Harbor IRSA"
  value       = aws_iam_role.harbor_s3.name
}

output "s3_policy_arn" {
  description = "ARN of the S3 access policy"
  value       = aws_iam_policy.harbor_s3_access.arn
}

output "kms_policy_arn" {
  description = "ARN of the KMS access policy"
  value       = aws_iam_policy.harbor_kms_access.arn
}

output "service_account_annotation" {
  description = "Annotation to add to Kubernetes service account"
  value       = "eks.amazonaws.com/role-arn: ${aws_iam_role.harbor_s3.arn}"
}
