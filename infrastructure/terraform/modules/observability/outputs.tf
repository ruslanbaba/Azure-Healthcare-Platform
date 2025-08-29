# Observability Module Outputs

# Azure Monitor Workspace
output "monitor_workspace_id" {
  description = "ID of the Azure Monitor workspace"
  value       = azurerm_monitor_workspace.main.id
}

output "monitor_workspace_name" {
  description = "Name of the Azure Monitor workspace"
  value       = azurerm_monitor_workspace.main.name
}

# Azure Managed Grafana
output "grafana_id" {
  description = "ID of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.main.id
}

output "grafana_name" {
  description = "Name of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.main.name
}

output "grafana_endpoint" {
  description = "Endpoint URL of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.main.endpoint
}

output "grafana_principal_id" {
  description = "Principal ID of the Grafana managed identity"
  value       = azurerm_dashboard_grafana.main.identity[0].principal_id
}

# Log Analytics Workspace
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "log_analytics_customer_id" {
  description = "Customer ID (Workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Application Insights
output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of the Application Insights instance"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights instance"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID of the Application Insights instance"
  value       = azurerm_application_insights.main.app_id
}

# Event Hub Namespace
output "eventhub_namespace_id" {
  description = "ID of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.monitoring.id
}

output "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.monitoring.name
}

output "eventhub_namespace_connection_string" {
  description = "Connection string of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.monitoring.default_primary_connection_string
  sensitive   = true
}

# Event Hubs
output "audit_eventhub_name" {
  description = "Name of the audit logs Event Hub"
  value       = azurerm_eventhub.audit_logs.name
}

output "application_eventhub_name" {
  description = "Name of the application logs Event Hub"
  value       = azurerm_eventhub.application_logs.name
}

output "security_eventhub_name" {
  description = "Name of the security logs Event Hub"
  value       = azurerm_eventhub.security_logs.name
}

# Prometheus Data Collection
output "prometheus_data_collection_endpoint_id" {
  description = "ID of the Prometheus data collection endpoint"
  value       = azurerm_monitor_workspace_data_collection_endpoint.prometheus.id
}

output "prometheus_data_collection_rule_id" {
  description = "ID of the Prometheus data collection rule"
  value       = azurerm_monitor_data_collection_rule.prometheus.id
}

# Storage Account
output "monitoring_storage_account_id" {
  description = "ID of the monitoring storage account"
  value       = azurerm_storage_account.monitoring.id
}

output "monitoring_storage_account_name" {
  description = "Name of the monitoring storage account"
  value       = azurerm_storage_account.monitoring.name
}

output "monitoring_storage_account_primary_key" {
  description = "Primary access key of the monitoring storage account"
  value       = azurerm_storage_account.monitoring.primary_access_key
  sensitive   = true
}

# Alert Action Group
output "critical_alert_action_group_id" {
  description = "ID of the critical alert action group"
  value       = azurerm_monitor_action_group.critical.id
}

output "critical_alert_action_group_name" {
  description = "Name of the critical alert action group"
  value       = azurerm_monitor_action_group.critical.name
}

# Private Endpoints
output "grafana_private_endpoint_ip" {
  description = "Private IP address of the Grafana private endpoint"
  value       = azurerm_private_endpoint.grafana.private_service_connection[0].private_ip_address
}

output "log_analytics_private_endpoint_ip" {
  description = "Private IP address of the Log Analytics private endpoint"
  value       = azurerm_private_endpoint.log_analytics.private_service_connection[0].private_ip_address
}

output "eventhub_private_endpoint_ip" {
  description = "Private IP address of the Event Hub private endpoint"
  value       = azurerm_private_endpoint.eventhub.private_service_connection[0].private_ip_address
}

# Workbook
output "healthcare_workbook_id" {
  description = "ID of the healthcare monitoring workbook"
  value       = azurerm_application_insights_workbook.healthcare_monitoring.id
}

# Connection Strings for Applications
output "monitoring_connection_strings" {
  description = "Connection strings for monitoring services"
  value = {
    application_insights = azurerm_application_insights.main.connection_string
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.workspace_id
    eventhub_audit = "${azurerm_eventhub_namespace.monitoring.default_primary_connection_string};EntityPath=${azurerm_eventhub.audit_logs.name}"
    eventhub_application = "${azurerm_eventhub_namespace.monitoring.default_primary_connection_string};EntityPath=${azurerm_eventhub.application_logs.name}"
    eventhub_security = "${azurerm_eventhub_namespace.monitoring.default_primary_connection_string};EntityPath=${azurerm_eventhub.security_logs.name}"
  }
  sensitive = true
}
