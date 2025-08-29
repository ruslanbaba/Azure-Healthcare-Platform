# Monitoring Module for Azure Healthcare Analytics Platform

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-${var.environment}-la-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                = "PerGB2018"
  retention_in_days   = var.retention_in_days
  
  # Data export rules for long-term retention
  daily_quota_gb = 10
  
  tags = merge(var.tags, {
    Purpose = "Monitoring"
  })
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "${var.project_name}-${var.environment}-ai-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  # Sampling settings for high-volume applications
  sampling_percentage = 20
  
  tags = var.tags
}

# Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "${var.project_name}-${var.environment}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = "health-ag"

  email_receiver {
    name          = "admin-email"
    email_address = var.admin_email
  }

  webhook_receiver {
    name        = "slack-webhook"
    service_uri = var.slack_webhook_url
  }

  tags = var.tags
}

# Metric Alerts
resource "azurerm_monitor_metric_alert" "cpu_usage" {
  name                = "${var.project_name}-${var.environment}-cpu-alert"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_cluster_id]
  description         = "High CPU usage in AKS cluster"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Insights.Container/nodes"
    metric_name      = "cpuUsagePercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "memory_usage" {
  name                = "${var.project_name}-${var.environment}-memory-alert"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_cluster_id]
  description         = "High memory usage in AKS cluster"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Insights.Container/nodes"
    metric_name      = "memoryWorkingSetPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = var.tags
}

# Log Analytics Solutions
resource "azurerm_log_analytics_solution" "container_insights" {
  solution_name         = "ContainerInsights"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }

  tags = var.tags
}

resource "azurerm_log_analytics_solution" "security_center" {
  solution_name         = "Security"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/Security"
  }

  tags = var.tags
}

# Workbook for healthcare analytics dashboard
resource "azurerm_application_insights_workbook" "healthcare_dashboard" {
  name                = "${var.project_name}-${var.environment}-dashboard"
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Healthcare Analytics Dashboard"
  
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Healthcare Analytics Platform Dashboard\n\nThis dashboard provides insights into the healthcare analytics platform performance and health."
        }
      }
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "Perf | where CounterName == \"% Processor Time\" | summarize avg(CounterValue) by bin(TimeGenerated, 5m)"
          size = 0
          title = "Average CPU Usage"
          timeContext = {
            durationMs = 3600000
          }
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
        }
      }
    ]
  })

  tags = var.tags
}

# Data Collection Rules for custom metrics
resource "azurerm_monitor_data_collection_rule" "healthcare" {
  name                = "${var.project_name}-${var.environment}-dcr"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
      name                  = "destination-log"
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["destination-log"]
  }

  data_sources {
    syslog {
      facility_names = ["auth", "authpriv", "cron", "daemon", "mark", "kern", "local0", "local1", "local2", "local3", "local4", "local5", "local6", "local7", "lpr", "mail", "news", "syslog", "user", "uucp"]
      log_levels     = ["Debug", "Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
      name           = "datasource-syslog"
    }
  }

  tags = var.tags
}

# Scheduled Query Alerts for healthcare-specific monitoring
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "failed_data_processing" {
  name                = "${var.project_name}-${var.environment}-data-processing-failures"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 1
  
  criteria {
    query                   = <<-QUERY
      traces
      | where severityLevel >= 3
      | where message contains "data processing"
      | summarize count() by bin(timestamp, 5m)
      | where count_ > 10
    QUERY
    time_aggregation_method = "Count"
    threshold               = 10
    operator                = "GreaterThan"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }

  tags = var.tags
}
