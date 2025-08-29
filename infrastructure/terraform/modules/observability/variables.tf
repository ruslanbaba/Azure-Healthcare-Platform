# Observability Module Variables

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

variable "virtual_network_id" {
  description = "ID of the virtual network"
  type        = string
}

variable "monitoring_subnet_id" {
  description = "ID of the monitoring subnet"
  type        = string
}

variable "storage_encryption_key_id" {
  description = "ID of the Key Vault key for storage encryption"
  type        = string
}

variable "storage_managed_identity_id" {
  description = "ID of the managed identity for storage encryption"
  type        = string
}

# Log Analytics Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  validation {
    condition = contains([
      "Free", "Standalone", "PerNode", "PerGB2018", "Premium"
    ], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid option."
  }
}

variable "log_analytics_retention_days" {
  description = "Retention period for Log Analytics workspace in days"
  type        = number
  default     = 90
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Retention days must be between 30 and 730."
  }
}

variable "log_analytics_daily_quota_gb" {
  description = "Daily quota for Log Analytics workspace in GB"
  type        = number
  default     = 100
  validation {
    condition     = var.log_analytics_daily_quota_gb >= 1
    error_message = "Daily quota must be at least 1 GB."
  }
}

# Application Insights Configuration
variable "application_insights_retention_days" {
  description = "Retention period for Application Insights in days"
  type        = number
  default     = 90
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Retention days must be between 30 and 730."
  }
}

variable "application_insights_daily_cap_gb" {
  description = "Daily data cap for Application Insights in GB"
  type        = number
  default     = 10
  validation {
    condition     = var.application_insights_daily_cap_gb >= 1
    error_message = "Daily cap must be at least 1 GB."
  }
}

# Alert Configuration
variable "alert_email_receivers" {
  description = "List of email receivers for alerts"
  type = list(object({
    name  = string
    email = string
  }))
  default = [
    {
      name  = "healthcare-admin"
      email = "admin@healthcare-platform.com"
    }
  ]
}

variable "alert_sms_receivers" {
  description = "List of SMS receivers for critical alerts"
  type = list(object({
    name         = string
    country_code = string
    phone_number = string
  }))
  default = []
}

variable "alert_function_app_id" {
  description = "Resource ID of the Azure Function App for alert handling"
  type        = string
  default     = ""
}

variable "alert_function_url" {
  description = "URL of the Azure Function for alert handling"
  type        = string
  default     = ""
}

# Monitoring Thresholds
variable "cpu_threshold_critical" {
  description = "CPU usage threshold for critical alerts (%)"
  type        = number
  default     = 90
  validation {
    condition     = var.cpu_threshold_critical >= 50 && var.cpu_threshold_critical <= 100
    error_message = "CPU threshold must be between 50 and 100."
  }
}

variable "memory_threshold_critical" {
  description = "Memory usage threshold for critical alerts (%)"
  type        = number
  default     = 85
  validation {
    condition     = var.memory_threshold_critical >= 50 && var.memory_threshold_critical <= 100
    error_message = "Memory threshold must be between 50 and 100."
  }
}

variable "disk_threshold_critical" {
  description = "Disk usage threshold for critical alerts (%)"
  type        = number
  default     = 80
  validation {
    condition     = var.disk_threshold_critical >= 50 && var.disk_threshold_critical <= 100
    error_message = "Disk threshold must be between 50 and 100."
  }
}

variable "response_time_threshold_ms" {
  description = "Response time threshold for alerts in milliseconds"
  type        = number
  default     = 5000
  validation {
    condition     = var.response_time_threshold_ms >= 1000
    error_message = "Response time threshold must be at least 1000ms."
  }
}

variable "error_rate_threshold" {
  description = "Error rate threshold for alerts (%)"
  type        = number
  default     = 5
  validation {
    condition     = var.error_rate_threshold >= 1 && var.error_rate_threshold <= 50
    error_message = "Error rate threshold must be between 1 and 50."
  }
}

# Security Monitoring
variable "failed_login_threshold" {
  description = "Failed login attempts threshold for security alerts"
  type        = number
  default     = 10
}

variable "suspicious_activity_threshold" {
  description = "Suspicious activity threshold for security alerts"
  type        = number
  default     = 5
}

# HIPAA Compliance Monitoring
variable "data_access_monitoring_enabled" {
  description = "Enable monitoring of data access patterns for HIPAA compliance"
  type        = bool
  default     = true
}

variable "audit_log_retention_years" {
  description = "Audit log retention period in years for HIPAA compliance"
  type        = number
  default     = 7
  validation {
    condition     = var.audit_log_retention_years >= 6
    error_message = "HIPAA requires audit logs to be retained for at least 6 years."
  }
}

variable "data_export_monitoring_enabled" {
  description = "Enable monitoring of data export activities"
  type        = bool
  default     = true
}

variable "encryption_monitoring_enabled" {
  description = "Enable monitoring of encryption status"
  type        = bool
  default     = true
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
    Purpose     = "Observability"
  }
}
