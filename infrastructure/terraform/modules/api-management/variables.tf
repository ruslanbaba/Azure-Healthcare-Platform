# API Management Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "healthcare-platform"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "unique_suffix" {
  description = "Unique suffix for resource names"
  type        = string
}

variable "publisher_name" {
  description = "Name of the API Management publisher"
  type        = string
  default     = "Healthcare Platform"
}

variable "publisher_email" {
  description = "Email of the API Management publisher"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

variable "sku_name" {
  description = "SKU name for API Management"
  type        = string
  default     = "Premium_1"
  validation {
    condition = contains([
      "Developer_1",
      "Basic_1", "Basic_2",
      "Standard_1", "Standard_2",
      "Premium_1", "Premium_2", "Premium_3", "Premium_4", "Premium_5", "Premium_6",
      "Consumption_0"
    ], var.sku_name)
    error_message = "SKU name must be a valid API Management SKU."
  }
}

variable "virtual_network_type" {
  description = "Type of virtual network integration (None, External, Internal)"
  type        = string
  default     = "Internal"
  validation {
    condition     = contains(["None", "External", "Internal"], var.virtual_network_type)
    error_message = "Virtual network type must be None, External, or Internal."
  }
}

variable "subnet_id" {
  description = "ID of the subnet for API Management (required for VNet integration)"
  type        = string
  default     = ""
}

variable "custom_domain_certificate_id" {
  description = "Key Vault certificate ID for custom domain"
  type        = string
  default     = ""
}

variable "gateway_hostname" {
  description = "Custom hostname for the API gateway"
  type        = string
  default     = ""
}

variable "developer_portal_hostname" {
  description = "Custom hostname for the developer portal"
  type        = string
  default     = ""
}

variable "management_hostname" {
  description = "Custom hostname for the management endpoint"
  type        = string
  default     = ""
}

variable "backend_service_url" {
  description = "URL of the backend service"
  type        = string
  default     = "https://backend.healthcare-platform.local"
}

variable "key_vault_url" {
  description = "URL of the Key Vault for storing secrets"
  type        = string
}

variable "key_vault_id" {
  description = "ID of the Key Vault"
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "allowed_origin" {
  description = "Allowed CORS origin"
  type        = string
  default     = "healthcare-platform.com"
}

variable "eventhub_connection_string" {
  description = "Event Hub connection string for logging"
  type        = string
  default     = ""
  sensitive   = true
}

variable "audit_eventhub_name" {
  description = "Name of the Event Hub for audit logs"
  type        = string
  default     = "audit-logs"
}

variable "error_eventhub_name" {
  description = "Name of the Event Hub for error logs"
  type        = string
  default     = "error-logs"
}

variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace for diagnostics"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Application = "healthcare-platform"
    ManagedBy   = "terraform"
    CostCenter  = "healthcare"
    Compliance  = "HIPAA"
  }
}
