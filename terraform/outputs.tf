# Root Outputs for Harbor IRSA Workshop

# EKS Cluster Outputs
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks_cluster.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = module.eks_cluster.cluster_version
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = module.eks_cluster.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = module.eks_cluster.oidc_provider_url
}

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.eks_cluster.vpc_id
}

# IRSA Outputs
output "harbor_iam_role_arn" {
  description = "ARN of the Harbor IAM role for IRSA"
  value       = module.irsa.role_arn
}

output "harbor_iam_role_name" {
  description = "Name of the Harbor IAM role"
  value       = module.irsa.role_name
}

output "service_account_annotation" {
  description = "Annotation for Kubernetes service account"
  value       = module.irsa.service_account_annotation
}

# S3 and KMS Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Harbor storage"
  value       = module.s3_kms.bucket_id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = module.s3_kms.bucket_arn
}

output "kms_key_id" {
  description = "ID of the KMS key"
  value       = module.s3_kms.kms_key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = module.s3_kms.kms_key_arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key"
  value       = module.s3_kms.kms_key_alias
}

# Harbor Outputs
output "harbor_namespace" {
  description = "Kubernetes namespace for Harbor"
  value       = module.harbor.namespace
}

output "harbor_service_account" {
  description = "Kubernetes service account for Harbor"
  value       = module.harbor.service_account_name
}

output "harbor_release_status" {
  description = "Status of Harbor Helm release"
  value       = module.harbor.release_status
}

output "harbor_chart_version" {
  description = "Version of Harbor Helm chart deployed"
  value       = module.harbor.chart_version
}

# Configuration Commands
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks_cluster.cluster_id}"
}

output "get_harbor_password" {
  description = "Command to get Harbor admin password"
  value       = "kubectl get secret -n ${module.harbor.namespace} ${var.harbor_release_name}-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 --decode"
}

output "get_harbor_url" {
  description = "Command to get Harbor LoadBalancer URL"
  value       = "kubectl get svc -n ${module.harbor.namespace} ${var.harbor_release_name}-portal -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
