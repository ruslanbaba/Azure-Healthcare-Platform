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

variable "subnet_id" {
  description = "Subnet ID for AKS cluster"
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault ID"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "node_count_min" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_count_max" {
  description = "Maximum number of nodes"
  type        = number
  default     = 10
}

variable "node_count_default" {
  description = "Default number of nodes"
  type        = number
  default     = 3
}

variable "vm_size" {
  description = "VM size for nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 100
}

variable "enable_auto_scaling" {
  description = "Enable auto scaling"
  type        = bool
  default     = true
}

variable "network_plugin" {
  description = "Network plugin"
  type        = string
  default     = "azure"
}

variable "network_policy" {
  description = "Network policy"
  type        = string
  default     = "calico"
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
  default     = ""
}

variable "admin_group_object_ids" {
  description = "Azure AD admin group object IDs"
  type        = list(string)
  default     = []
}

variable "container_registry_id" {
  description = "Container Registry ID"
  type        = string
  default     = ""
}

variable "vnet_id" {
  description = "Virtual network ID"
  type        = string
  default     = ""
}
