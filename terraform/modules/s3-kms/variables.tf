# Variables for S3 and KMS Module

variable "bucket_name" {
  description = "Name of the S3 bucket for Harbor storage"
  type        = string
}

variable "harbor_role_arn" {
  description = "ARN of the Harbor IAM role that needs access to the bucket"
  type        = string
}

variable "kms_deletion_window" {
  description = "Number of days before KMS key is deleted after destruction"
  type        = number
  default     = 30
}

variable "enable_lifecycle_rules" {
  description = "Enable S3 lifecycle rules for old version cleanup"
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days to retain noncurrent object versions"
  type        = number
  default     = 90
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
