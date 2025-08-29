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

variable "key_vault_id" {
  description = "Key Vault ID for customer-managed encryption"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for network rules"
  type        = string
}

variable "encryption_key_id" {
  description = "Customer-managed encryption key ID"
  type        = string
  default     = ""
}

variable "managed_identity_id" {
  description = "Managed identity ID for encryption"
  type        = string
  default     = ""
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

variable "functions_principal_id" {
  description = "Functions principal ID for role assignment"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
}
