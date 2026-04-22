variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Project     = "platform-bootstrap"
    CostCenter  = "engineering"
  }
}

# Networking
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_cidr" {
  description = "CIDR block for AKS node subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "pod_subnet_cidr" {
  description = "CIDR block for AKS pod subnet (Azure CNI)"
  type        = string
  default     = "10.0.2.0/23"
}

variable "private_endpoint_subnet_cidr" {
  description = "CIDR block for private endpoint subnet"
  type        = string
  default     = "10.0.4.0/24"
}

# AKS
variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.28"
}

variable "system_node_pool" {
  description = "Configuration for the system node pool"
  type = object({
    vm_size    = string
    node_count = number
    min_count  = number
    max_count  = number
  })
  default = {
    vm_size    = "Standard_D4s_v5"
    node_count = 2
    min_count  = 2
    max_count  = 5
  }
}

variable "workload_node_pool" {
  description = "Configuration for the workload node pool"
  type = object({
    vm_size   = string
    min_count = number
    max_count = number
  })
  default = {
    vm_size   = "Standard_D8s_v5"
    min_count = 2
    max_count = 20
  }
}

variable "admin_group_object_ids" {
  description = "Azure AD group object IDs granted cluster-admin access"
  type        = list(string)
  sensitive   = true
}

# Monitoring
variable "log_retention_days" {
  description = "Log Analytics workspace retention in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}
