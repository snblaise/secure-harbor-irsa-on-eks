# Variables for Harbor Helm Module

variable "release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "harbor"
}

variable "namespace" {
  description = "Kubernetes namespace for Harbor"
  type        = string
  default     = "harbor"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for Harbor"
  type        = string
  default     = "harbor-registry"
}

variable "iam_role_arn" {
  description = "ARN of the IAM role for IRSA"
  type        = string
}

variable "harbor_chart_version" {
  description = "Version of the Harbor Helm chart"
  type        = string
  default     = "1.13.0"
}

variable "expose_type" {
  description = "How to expose Harbor service (ingress, clusterIP, nodePort, loadBalancer)"
  type        = string
  default     = "loadBalancer"
}

variable "enable_tls" {
  description = "Enable TLS for Harbor"
  type        = bool
  default     = true
}

variable "tls_cert_source" {
  description = "Source of TLS certificate (auto, secret, none)"
  type        = string
  default     = "auto"
}

variable "external_url" {
  description = "External URL for accessing Harbor"
  type        = string
  default     = ""
}

variable "loadbalancer_annotations" {
  description = "Annotations for the LoadBalancer service"
  type        = map(string)
  default     = {}
}

variable "storage_class" {
  description = "Storage class for persistent volumes"
  type        = string
  default     = "gp3"
}

variable "registry_storage_size" {
  description = "Size of registry persistent volume"
  type        = string
  default     = "10Gi"
}

variable "database_storage_size" {
  description = "Size of database persistent volume"
  type        = string
  default     = "5Gi"
}

variable "redis_storage_size" {
  description = "Size of Redis persistent volume"
  type        = string
  default     = "1Gi"
}

variable "s3_region" {
  description = "AWS region for S3 bucket"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of S3 bucket for Harbor storage"
  type        = string
}

variable "admin_password" {
  description = "Admin password for Harbor"
  type        = string
  sensitive   = true
  default     = "Harbor12345"
}

variable "core_replicas" {
  description = "Number of Harbor core replicas"
  type        = number
  default     = 1
}

variable "core_resources" {
  description = "Resource requests and limits for Harbor core"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "registry_replicas" {
  description = "Number of Harbor registry replicas"
  type        = number
  default     = 1
}

variable "registry_resources" {
  description = "Resource requests and limits for Harbor registry"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "portal_replicas" {
  description = "Number of Harbor portal replicas"
  type        = number
  default     = 1
}

variable "portal_resources" {
  description = "Resource requests and limits for Harbor portal"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "256Mi"
    }
  }
}

variable "jobservice_replicas" {
  description = "Number of Harbor jobservice replicas"
  type        = number
  default     = 1
}

variable "jobservice_resources" {
  description = "Resource requests and limits for Harbor jobservice"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "enable_trivy" {
  description = "Enable Trivy vulnerability scanner"
  type        = bool
  default     = true
}

variable "trivy_replicas" {
  description = "Number of Trivy replicas"
  type        = number
  default     = 1
}

variable "trivy_resources" {
  description = "Resource requests and limits for Trivy"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "200m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1000m"
      memory = "1Gi"
    }
  }
}

variable "database_resources" {
  description = "Resource requests and limits for database"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "redis_resources" {
  description = "Resource requests and limits for Redis"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "256Mi"
    }
  }
}
