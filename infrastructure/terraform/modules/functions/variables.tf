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

variable "sku_name" {
  description = "Service plan SKU name"
  type        = string
  default     = "EP2"
}

variable "storage_account_name" {
  description = "Storage account name for Functions"
  type        = string
}

variable "storage_account_access_key" {
  description = "Storage account access key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "storage_account_id" {
  description = "Storage account ID for role assignments"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID for VNet integration"
  type        = string
  default     = ""
}

variable "key_vault_id" {
  description = "Key Vault ID"
  type        = string
  default     = ""
}

variable "key_vault_url" {
  description = "Key Vault URL"
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
  default     = ""
}

variable "application_insights_key" {
  description = "Application Insights instrumentation key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "application_insights_connection_string" {
  description = "Application Insights connection string"
  type        = string
  sensitive   = true
  default     = ""
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  type        = string
  default     = ""
}

variable "cors_allowed_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = []
}

variable "additional_app_settings" {
  description = "Additional app settings"
  type        = map(string)
  default     = {}
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

variable "enable_staging_slot" {
  description = "Enable staging slot for blue-green deployments"
  type        = bool
  default     = false
}
