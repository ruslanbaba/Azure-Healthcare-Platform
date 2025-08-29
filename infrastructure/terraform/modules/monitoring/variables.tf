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

variable "retention_in_days" {
  description = "Log retention period in days"
  type        = number
  default     = 90
}

variable "admin_email" {
  description = "Admin email for alerts"
  type        = string
  default     = "admin@healthcareanalytics.com"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
}

variable "aks_cluster_id" {
  description = "AKS cluster ID for monitoring"
  type        = string
  default     = ""
}
