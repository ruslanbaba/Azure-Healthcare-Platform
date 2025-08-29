# Input Variables for Azure Healthcare Analytics Platform

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "healthcare-analytics"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US 2"
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East",
      "North Europe", "West Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "Healthcare Analytics Team"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "IT-Healthcare"
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_config" {
  description = "Subnet configuration"
  type = map(object({
    address_prefixes = list(string)
    service_endpoints = list(string)
  }))
  default = {
    aks = {
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    }
    data = {
      address_prefixes  = ["10.0.2.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
    functions = {
      address_prefixes  = ["10.0.3.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Web"]
    }
    apim = {
      address_prefixes  = ["10.0.4.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
    gateway = {
      address_prefixes  = ["10.0.5.0/24"]
      service_endpoints = []
    }
  }
}

# AKS Configuration
variable "aks_config" {
  description = "AKS cluster configuration"
  type = object({
    kubernetes_version = string
    node_count_min     = number
    node_count_max     = number
    node_count_default = number
    vm_size           = string
    os_disk_size_gb   = number
    enable_auto_scaling = bool
    enable_rbac        = bool
    network_plugin     = string
    network_policy     = string
  })
  default = {
    kubernetes_version = "1.28"
    node_count_min     = 2
    node_count_max     = 10
    node_count_default = 3
    vm_size           = "Standard_D4s_v3"
    os_disk_size_gb   = 100
    enable_auto_scaling = true
    enable_rbac        = true
    network_plugin     = "azure"
    network_policy     = "calico"
  }
}

# Data Lake Configuration
variable "data_lake_config" {
  description = "Data Lake configuration"
  type = object({
    account_tier             = string
    account_replication_type = string
    is_hns_enabled          = bool
    min_tls_version         = string
    containers              = list(string)
  })
  default = {
    account_tier             = "Standard"
    account_replication_type = "ZRS"
    is_hns_enabled          = true
    min_tls_version         = "TLS1_2"
    containers              = ["raw", "processed", "curated", "logs", "backups"]
  }
}

# Function App Configuration
variable "function_config" {
  description = "Azure Functions configuration"
  type = object({
    runtime_version = string
    runtime_stack   = string
    sku_name       = string
  })
  default = {
    runtime_version = "~4"
    runtime_stack   = "python"
    sku_name       = "EP2"
  }
}

# API Management Configuration
variable "apim_config" {
  description = "API Management configuration"
  type = object({
    sku_name          = string
    publisher_name    = string
    publisher_email   = string
  })
  default = {
    sku_name          = "Standard_v2"
    publisher_name    = "Healthcare Analytics"
    publisher_email   = "admin@healthcareanalytics.com"
  }
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "Allowed IP ranges for access"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for services"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 2555
    error_message = "Backup retention days must be between 7 and 2555."
  }
}

# Monitoring Configuration
variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 90
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for all resources"
  type        = bool
  default     = true
}

# Container Registry Configuration
variable "acr_config" {
  description = "Azure Container Registry configuration"
  type = object({
    sku                = string
    admin_enabled      = bool
    public_network_access_enabled = bool
  })
  default = {
    sku                = "Premium"
    admin_enabled      = false
    public_network_access_enabled = false
  }
}
