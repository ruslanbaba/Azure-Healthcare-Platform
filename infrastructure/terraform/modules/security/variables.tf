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

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "object_id" {
  description = "Object ID of the user or service principal"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "allowed_subnet_ids" {
  description = "List of subnet IDs allowed to access Key Vault"
  type        = list(string)
  default     = []
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

variable "gateway_subnet_id" {
  description = "Application Gateway subnet ID"
  type        = string
  default     = ""
}

variable "gateway_public_ip_id" {
  description = "Application Gateway public IP ID"
  type        = string
  default     = ""
}
