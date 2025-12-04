# Main Terraform Configuration for Harbor IRSA Workshop
# Orchestrates all modules to deploy complete infrastructure

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# Get current AWS account and region info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# EKS Cluster Module
module "eks_cluster" {
  source = "./modules/eks-cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  cluster_log_types = var.cluster_log_types
  common_tags       = var.common_tags
}

# Configure Kubernetes provider after EKS cluster is created
provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks_cluster.cluster_id,
      "--region",
      var.aws_region
    ]
  }
}

# Configure Helm provider after EKS cluster is created
provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks_cluster.cluster_id,
        "--region",
        var.aws_region
      ]
    }
  }
}

# S3 and KMS Module (must be created before IRSA module due to dependency)
module "s3_kms" {
  source = "./modules/s3-kms"

  bucket_name     = "${var.s3_bucket_prefix}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  harbor_role_arn = module.irsa.role_arn
  common_tags     = var.common_tags

  kms_deletion_window                = var.kms_deletion_window
  enable_lifecycle_rules             = var.enable_lifecycle_rules
  noncurrent_version_expiration_days = var.noncurrent_version_expiration_days

  depends_on = [module.eks_cluster]
}

# IRSA Module
module "irsa" {
  source = "./modules/irsa"

  role_name            = "${var.cluster_name}-harbor-s3-role"
  oidc_provider_arn    = module.eks_cluster.oidc_provider_arn
  oidc_provider_id     = module.eks_cluster.oidc_provider_id
  namespace            = var.harbor_namespace
  service_account_name = var.harbor_service_account_name
  s3_bucket_arn        = module.s3_kms.bucket_arn
  kms_key_arn          = module.s3_kms.kms_key_arn
  aws_region           = var.aws_region
  common_tags          = var.common_tags

  depends_on = [module.eks_cluster]
}

# Harbor Helm Module
module "harbor" {
  source = "./modules/harbor-helm"

  release_name         = var.harbor_release_name
  namespace            = var.harbor_namespace
  service_account_name = var.harbor_service_account_name
  iam_role_arn         = module.irsa.role_arn

  harbor_chart_version = var.harbor_chart_version
  expose_type          = var.harbor_expose_type
  enable_tls           = var.harbor_enable_tls
  tls_cert_source      = var.harbor_tls_cert_source
  external_url         = var.harbor_external_url

  storage_class         = var.harbor_storage_class
  registry_storage_size = var.harbor_registry_storage_size
  database_storage_size = var.harbor_database_storage_size
  redis_storage_size    = var.harbor_redis_storage_size

  s3_region      = var.aws_region
  s3_bucket_name = module.s3_kms.bucket_id
  admin_password = var.harbor_admin_password

  core_replicas       = var.harbor_core_replicas
  registry_replicas   = var.harbor_registry_replicas
  portal_replicas     = var.harbor_portal_replicas
  jobservice_replicas = var.harbor_jobservice_replicas
  enable_trivy        = var.harbor_enable_trivy
  trivy_replicas      = var.harbor_trivy_replicas

  depends_on = [
    module.eks_cluster,
    module.irsa,
    module.s3_kms
  ]
}
