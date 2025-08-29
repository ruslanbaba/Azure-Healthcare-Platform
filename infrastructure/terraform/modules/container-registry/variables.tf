variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "unique_suffix" {
  description = "Unique suffix for resource names"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "sku" {
  description = "Container Registry SKU"
  type        = string
  default     = "Premium"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be Basic, Standard, or Premium."
  }
}

variable "admin_enabled" {
  description = "Enable admin user"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Enable public network access"
  type        = bool
  default     = false
}

variable "georeplications" {
  description = "Geo-replication configuration for Premium SKU"
  type = list(object({
    location                  = string
    zone_redundancy_enabled   = bool
    regional_endpoint_enabled = bool
  }))
  default = []
}

variable "allowed_subnet_ids" {
  description = "List of subnet IDs allowed to access the registry"
  type        = list(string)
  default     = []
}

variable "retention_days" {
  description = "Retention policy days"
  type        = number
  default     = 7
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints"
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
  default     = ""
}

variable "vnet_id" {
  description = "Virtual network ID"
  type        = string
  default     = ""
}

variable "aks_principal_id" {
  description = "AKS principal ID for role assignment"
  type        = string
  default     = ""
}

variable "key_vault_id" {
  description = "Key Vault ID"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  type        = string
  default     = ""
}

variable "enable_build_tasks" {
  description = "Enable ACR build tasks"
  type        = bool
  default     = false
}

variable "github_token" {
  description = "GitHub personal access token for ACR tasks"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_security_scanning" {
  description = "Enable security scanning webhook"
  type        = bool
  default     = true
}

variable "security_scan_webhook_url" {
  description = "Webhook URL for security scanning"
  type        = string
  default     = ""
}
