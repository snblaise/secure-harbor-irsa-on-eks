# Harbor Helm Deployment Module
# Deploys Harbor container registry using Helm with IRSA configuration

terraform {
  required_version = ">= 1.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# Create Harbor namespace
resource "kubernetes_namespace" "harbor" {
  metadata {
    name = var.namespace

    labels = {
      name = var.namespace
    }
  }
}

# Create Kubernetes Service Account with IRSA annotation
resource "kubernetes_service_account" "harbor" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.harbor.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = var.iam_role_arn
    }

    labels = {
      "app.kubernetes.io/name"       = "harbor"
      "app.kubernetes.io/component"  = "registry"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Harbor Helm Release
resource "helm_release" "harbor" {
  name       = var.release_name
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = var.harbor_chart_version
  namespace  = kubernetes_namespace.harbor.metadata[0].name

  # Wait for resources to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  # Harbor configuration values
  values = [
    yamlencode({
      # Expose Harbor via LoadBalancer
      expose = {
        type = var.expose_type
        tls = {
          enabled    = var.enable_tls
          certSource = var.tls_cert_source
        }
        loadBalancer = {
          annotations = var.loadbalancer_annotations
        }
      }

      # External URL configuration
      externalURL = var.external_url

      # Persistence configuration
      persistence = {
        enabled = true
        persistentVolumeClaim = {
          registry = {
            storageClass = var.storage_class
            size         = var.registry_storage_size
          }
          database = {
            storageClass = var.storage_class
            size         = var.database_storage_size
          }
          redis = {
            storageClass = var.storage_class
            size         = var.redis_storage_size
          }
        }
      }

      # S3 storage backend configuration with IRSA
      imageChartStorage = {
        type = "s3"
        s3 = {
          region         = var.s3_region
          bucket         = var.s3_bucket_name
          encrypt        = true
          secure         = true
          v4auth         = true
          regionendpoint = "s3.${var.s3_region}.amazonaws.com"
          # No accesskey or secretkey - IRSA provides credentials automatically
        }
      }

      # Service account configuration
      serviceAccount = {
        create = false # We create it separately above
        name   = kubernetes_service_account.harbor.metadata[0].name
      }

      # Core component configuration
      core = {
        serviceAccountName = kubernetes_service_account.harbor.metadata[0].name
        replicas           = var.core_replicas
        resources          = var.core_resources
      }

      # Registry component configuration
      registry = {
        serviceAccountName = kubernetes_service_account.harbor.metadata[0].name
        replicas           = var.registry_replicas
        resources          = var.registry_resources
      }

      # Portal configuration
      portal = {
        replicas  = var.portal_replicas
        resources = var.portal_resources
      }

      # JobService configuration
      jobservice = {
        serviceAccountName = kubernetes_service_account.harbor.metadata[0].name
        replicas           = var.jobservice_replicas
        resources          = var.jobservice_resources
      }

      # Trivy scanner configuration
      trivy = {
        enabled   = var.enable_trivy
        replicas  = var.trivy_replicas
        resources = var.trivy_resources
      }

      # Database configuration
      database = {
        type = "internal"
        internal = {
          resources = var.database_resources
        }
      }

      # Redis configuration
      redis = {
        type = "internal"
        internal = {
          resources = var.redis_resources
        }
      }

      # Admin password
      harborAdminPassword = var.admin_password
    })
  ]

  depends_on = [
    kubernetes_namespace.harbor,
    kubernetes_service_account.harbor
  ]
}
