# Variables for IRSA Module

variable "role_name" {
  description = "Name of the IAM role for Harbor IRSA"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
}

variable "oidc_provider_id" {
  description = "ID of the EKS OIDC provider (without https://)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where Harbor service account exists"
  type        = string
  default     = "harbor"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for Harbor"
  type        = string
  default     = "harbor-registry"
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Harbor storage"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for S3 encryption"
  type        = string
}

variable "aws_region" {
  description = "AWS region for KMS ViaService condition"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
