# Observability Stack Module for Azure Healthcare Analytics Platform
# Comprehensive monitoring with Prometheus, Grafana, Loki, Tempo, and AlertManager

# Azure Monitor Workspace for unified observability
resource "azurerm_monitor_workspace" "main" {
  name                = "${var.project_name}-${var.environment}-monitor-workspace-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  tags = merge(var.tags, {
    Purpose = "Observability"
    Component = "Monitoring"
  })
}

# Azure Managed Grafana
resource "azurerm_dashboard_grafana" "main" {
  name                              = "${var.project_name}-${var.environment}-grafana-${var.unique_suffix}"
  resource_group_name               = var.resource_group_name
  location                          = var.location
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = false
  zone_redundancy_enabled           = true
  
  # Azure Monitor integration
  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.main.id
  }
  
  # Identity for accessing Azure resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    Purpose = "Visualization"
    Component = "Grafana"
  })
}

# Azure Managed Prometheus
resource "azurerm_monitor_workspace_data_collection_endpoint" "prometheus" {
  name                = "${var.project_name}-${var.environment}-prometheus-dce-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  
  public_network_access_enabled = false
  
  tags = var.tags
}

# Data Collection Rule for Prometheus
resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "${var.project_name}-${var.environment}-prometheus-dcr-${var.unique_suffix}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_workspace_data_collection_endpoint.prometheus.id
  kind                       = "Linux"
  description                = "Data collection rule for Prometheus metrics"

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.main.id
      name              = "MonitoringAccount1"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  tags = var.tags
}

# Application Insights for detailed application monitoring
resource "azurerm_application_insights" "main" {
  name                = "${var.project_name}-${var.environment}-appinsights-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_days
  daily_data_cap_in_gb = var.application_insights_daily_cap_gb
  
  # Disable public network access
  internet_ingestion_enabled = false
  internet_query_enabled     = false
  
  tags = merge(var.tags, {
    Purpose = "ApplicationMonitoring"
    Component = "ApplicationInsights"
  })
}

# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-${var.environment}-logs-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  daily_quota_gb      = var.log_analytics_daily_quota_gb
  
  # Enhanced security
  internet_ingestion_enabled = false
  internet_query_enabled     = false
  
  tags = merge(var.tags, {
    Purpose = "CentralizedLogging"
    Component = "LogAnalytics"
  })
}

# Event Hub Namespace for high-throughput logging
resource "azurerm_eventhub_namespace" "monitoring" {
  name                = "${var.project_name}-${var.environment}-eventhub-mon-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  capacity            = 2
  
  # Enhanced security
  public_network_access_enabled = false
  minimum_tls_version           = "1.2"
  
  # Auto-inflate for scaling
  auto_inflate_enabled     = true
  maximum_throughput_units = 10
  
  # Network rules
  network_rulesets {
    default_action                 = "Deny"
    public_network_access_enabled  = false
    trusted_service_access_enabled = true
    
    virtual_network_rule {
      subnet_id = var.monitoring_subnet_id
    }
  }
  
  tags = merge(var.tags, {
    Purpose = "HighThroughputLogging"
    Component = "EventHub"
  })
}

# Event Hubs for different log types
resource "azurerm_eventhub" "audit_logs" {
  name                = "audit-logs"
  namespace_name      = azurerm_eventhub_namespace.monitoring.name
  resource_group_name = var.resource_group_name
  partition_count     = 4
  message_retention   = 7
  
  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
    skip_empty_archives = true
    
    destination {
      name                = "EventHubArchive"
      archive_name_format = "audit-logs/{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.monitoring_archive.name
      storage_account_id  = azurerm_storage_account.monitoring.id
    }
  }
}

resource "azurerm_eventhub" "application_logs" {
  name                = "application-logs"
  namespace_name      = azurerm_eventhub_namespace.monitoring.name
  resource_group_name = var.resource_group_name
  partition_count     = 8
  message_retention   = 3
  
  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
    skip_empty_archives = true
    
    destination {
      name                = "EventHubArchive"
      archive_name_format = "app-logs/{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.monitoring_archive.name
      storage_account_id  = azurerm_storage_account.monitoring.id
    }
  }
}

resource "azurerm_eventhub" "security_logs" {
  name                = "security-logs"
  namespace_name      = azurerm_eventhub_namespace.monitoring.name
  resource_group_name = var.resource_group_name
  partition_count     = 2
  message_retention   = 30
  
  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
    skip_empty_archives = true
    
    destination {
      name                = "EventHubArchive"
      archive_name_format = "security-logs/{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.monitoring_archive.name
      storage_account_id  = azurerm_storage_account.monitoring.id
    }
  }
}

# Storage Account for log archiving
resource "azurerm_storage_account" "monitoring" {
  name                            = "${var.project_name}${var.environment}mon${var.unique_suffix}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  
  # Advanced security
  infrastructure_encryption_enabled = true
  
  # Customer-managed encryption
  customer_managed_key {
    key_vault_key_id          = var.storage_encryption_key_id
    user_assigned_identity_id = var.storage_managed_identity_id
  }
  
  identity {
    type         = "UserAssigned"
    identity_ids = [var.storage_managed_identity_id]
  }
  
  # Network rules
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    
    virtual_network_subnet_ids = [var.monitoring_subnet_id]
  }
  
  # Lifecycle management
  blob_properties {
    delete_retention_policy {
      days = 90
    }
    
    container_delete_retention_policy {
      days = 90
    }
    
    versioning_enabled       = true
    change_feed_enabled      = true
    change_feed_retention_in_days = 30
  }
  
  tags = merge(var.tags, {
    Purpose = "MonitoringArchive"
    Component = "Storage"
  })
}

resource "azurerm_storage_container" "monitoring_archive" {
  name                  = "monitoring-archive"
  storage_account_name  = azurerm_storage_account.monitoring.name
  container_access_type = "private"
}

# Private Endpoints for secure access
resource "azurerm_private_endpoint" "grafana" {
  name                = "${azurerm_dashboard_grafana.main.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.monitoring_subnet_id

  private_service_connection {
    name                           = "${azurerm_dashboard_grafana.main.name}-psc"
    private_connection_resource_id = azurerm_dashboard_grafana.main.id
    subresource_names              = ["grafana"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "grafana-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.grafana.id]
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "log_analytics" {
  name                = "${azurerm_log_analytics_workspace.main.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.monitoring_subnet_id

  private_service_connection {
    name                           = "${azurerm_log_analytics_workspace.main.name}-psc"
    private_connection_resource_id = azurerm_log_analytics_workspace.main.id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "monitor-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.monitor.id]
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "eventhub" {
  name                = "${azurerm_eventhub_namespace.monitoring.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.monitoring_subnet_id

  private_service_connection {
    name                           = "${azurerm_eventhub_namespace.monitoring.name}-psc"
    private_connection_resource_id = azurerm_eventhub_namespace.monitoring.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "eventhub-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.eventhub.id]
  }

  tags = var.tags
}

# Private DNS Zones
resource "azurerm_private_dns_zone" "grafana" {
  name                = "privatelink.grafana.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "monitor" {
  name                = "privatelink.monitor.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "eventhub" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# DNS Zone Virtual Network Links
resource "azurerm_private_dns_zone_virtual_network_link" "grafana" {
  name                  = "grafana-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.grafana.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "monitor" {
  name                  = "monitor-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.monitor.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventhub" {
  name                  = "eventhub-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.eventhub.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

# Alert Action Group for critical alerts
resource "azurerm_monitor_action_group" "critical" {
  name                = "${var.project_name}-${var.environment}-critical-alerts"
  resource_group_name = var.resource_group_name
  short_name          = "critalerts"
  enabled             = true

  # Email notifications
  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name          = email_receiver.value.name
      email_address = email_receiver.value.email
    }
  }

  # SMS notifications for critical issues
  dynamic "sms_receiver" {
    for_each = var.alert_sms_receivers
    content {
      name         = sms_receiver.value.name
      country_code = sms_receiver.value.country_code
      phone_number = sms_receiver.value.phone_number
    }
  }

  # Azure Function webhook for automated responses
  azure_function_receiver {
    name                     = "automated-response"
    function_app_resource_id = var.alert_function_app_id
    function_name            = "alert-handler"
    http_trigger_url         = var.alert_function_url
    use_common_alert_schema  = true
  }

  tags = var.tags
}

# Diagnostic Settings for comprehensive monitoring
resource "azurerm_monitor_diagnostic_setting" "eventhub" {
  name                       = "${azurerm_eventhub_namespace.monitoring.name}-diagnostics"
  target_resource_id         = azurerm_eventhub_namespace.monitoring.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "ArchiveLogs"
  }

  enabled_log {
    category = "OperationalLogs"
  }

  enabled_log {
    category = "AutoScaleLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Workbook for healthcare-specific monitoring
resource "azurerm_application_insights_workbook" "healthcare_monitoring" {
  name                = "${var.project_name}-${var.environment}-healthcare-workbook"
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Healthcare Platform Monitoring"
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Healthcare Platform Observability Dashboard\n\nComprehensive monitoring for HIPAA-compliant healthcare analytics platform"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "requests | where timestamp > ago(1h) | summarize count() by bin(timestamp, 5m)"
          size = 0
          title = "Request Volume (Last Hour)"
        }
      }
    ]
  })

  tags = var.tags
}
