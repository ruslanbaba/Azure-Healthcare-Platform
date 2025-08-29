variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
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

variable "application_insights_id" {
  description = "Application Insights resource ID"
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault resource ID"
  type        = string
}

variable "storage_account_id" {
  description = "Storage account resource ID"
  type        = string
}

variable "container_registry_id" {
  description = "Container registry resource ID"
  type        = string
}

variable "ml_encryption_key_id" {
  description = "ML workspace encryption key ID"
  type        = string
}

variable "synapse_encryption_key_id" {
  description = "Synapse workspace encryption key ID"
  type        = string
}

variable "data_lake_filesystem_id" {
  description = "Data Lake Gen2 filesystem ID"
  type        = string
}

variable "synapse_admin_password" {
  description = "Synapse SQL administrator password"
  type        = string
  sensitive   = true
}

variable "aad_admin_login" {
  description = "Azure AD admin login"
  type        = string
}

variable "aad_admin_object_id" {
  description = "Azure AD admin object ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "ml_subnet_id" {
  description = "Machine Learning subnet ID"
  type        = string
}

variable "vnet_id" {
  description = "Virtual Network ID"
  type        = string
}
