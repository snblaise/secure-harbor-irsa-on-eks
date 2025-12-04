# Root Variables for Harbor IRSA Workshop

# AWS Configuration
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

# EKS Cluster Configuration
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "harbor-irsa-workshop"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "node_instance_types" {
  description = "Instance types for EKS node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type for node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 4
}

variable "cluster_log_types" {
  description = "EKS control plane logging types"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

# S3 and KMS Configuration
variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (will be suffixed with account-region)"
  type        = string
  default     = "harbor-registry-storage"
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

variable "enable_lifecycle_rules" {
  description = "Enable S3 lifecycle rules"
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Days to retain noncurrent object versions"
  type        = number
  default     = 90
}

# Harbor Configuration
variable "harbor_namespace" {
  description = "Kubernetes namespace for Harbor"
  type        = string
  default     = "harbor"
}

variable "harbor_service_account_name" {
  description = "Kubernetes service account name for Harbor"
  type        = string
  default     = "harbor-registry"
}

variable "harbor_release_name" {
  description = "Helm release name for Harbor"
  type        = string
  default     = "harbor"
}

variable "harbor_chart_version" {
  description = "Harbor Helm chart version"
  type        = string
  default     = "1.13.0"
}

variable "harbor_expose_type" {
  description = "How to expose Harbor (loadBalancer, ingress, nodePort, clusterIP)"
  type        = string
  default     = "loadBalancer"
}

variable "harbor_enable_tls" {
  description = "Enable TLS for Harbor"
  type        = bool
  default     = true
}

variable "harbor_tls_cert_source" {
  description = "TLS certificate source (auto, secret, none)"
  type        = string
  default     = "auto"
}

variable "harbor_external_url" {
  description = "External URL for Harbor (leave empty for auto-detection)"
  type        = string
  default     = ""
}

variable "harbor_storage_class" {
  description = "Storage class for Harbor persistent volumes"
  type        = string
  default     = "gp3"
}

variable "harbor_registry_storage_size" {
  description = "Size of registry persistent volume"
  type        = string
  default     = "10Gi"
}

variable "harbor_database_storage_size" {
  description = "Size of database persistent volume"
  type        = string
  default     = "5Gi"
}

variable "harbor_redis_storage_size" {
  description = "Size of Redis persistent volume"
  type        = string
  default     = "1Gi"
}

variable "harbor_admin_password" {
  description = "Admin password for Harbor"
  type        = string
  sensitive   = true
  default     = "Harbor12345"
}

variable "harbor_core_replicas" {
  description = "Number of Harbor core replicas"
  type        = number
  default     = 1
}

variable "harbor_registry_replicas" {
  description = "Number of Harbor registry replicas"
  type        = number
  default     = 1
}

variable "harbor_portal_replicas" {
  description = "Number of Harbor portal replicas"
  type        = number
  default     = 1
}

variable "harbor_jobservice_replicas" {
  description = "Number of Harbor jobservice replicas"
  type        = number
  default     = 1
}

variable "harbor_enable_trivy" {
  description = "Enable Trivy vulnerability scanner"
  type        = bool
  default     = true
}

variable "harbor_trivy_replicas" {
  description = "Number of Trivy replicas"
  type        = number
  default     = 1
}

# Common Tags
variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "harbor-irsa-workshop"
    Environment = "workshop"
    ManagedBy   = "terraform"
  }
}
