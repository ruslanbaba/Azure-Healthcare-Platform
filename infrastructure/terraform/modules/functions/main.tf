# Azure Functions Module for Azure Healthcare Analytics Platform

# Service Plan for Azure Functions
resource "azurerm_service_plan" "functions" {
  name                = "${var.project_name}-${var.environment}-functions-plan-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name           = var.sku_name
  
  tags = merge(var.tags, {
    Purpose = "Serverless Functions"
  })
}

# Function App
resource "azurerm_linux_function_app" "main" {
  name                = "${var.project_name}-${var.environment}-func-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  storage_account_name       = var.storage_account_name
  storage_account_access_key = var.storage_account_access_key
  service_plan_id           = azurerm_service_plan.functions.id
  
  # HTTPS only for security
  https_only = true
  
  # Identity configuration
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.functions.id]
  }
  
  # Site configuration
  site_config {
    minimum_tls_version = "1.2"
    ftps_state         = "Disabled"
    
    # CORS configuration
    cors {
      allowed_origins = var.cors_allowed_origins
      support_credentials = false
    }
    
    # Application stack
    application_stack {
      python_version = "3.11"
    }
    
    # Always on for better performance
    always_on = var.sku_name != "Y1"  # Not available for Consumption plan
    
    # Application insights
    application_insights_key               = var.application_insights_key
    application_insights_connection_string = var.application_insights_connection_string
  }
  
  # App settings
  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME"                    = "python"
    "PYTHON_THREADPOOL_THREAD_COUNT"             = "4"
    "AZURE_CLIENT_ID"                            = azurerm_user_assigned_identity.functions.client_id
    "KEY_VAULT_URL"                              = var.key_vault_url
    "STORAGE_ACCOUNT_NAME"                       = var.storage_account_name
    "APPLICATIONINSIGHTS_CONNECTION_STRING"       = var.application_insights_connection_string
    "AzureWebJobsFeatureFlags"                   = "EnableWorkerIndexing"
    "FUNCTIONS_EXTENSION_VERSION"                 = "~4"
    "ENABLE_ORYX_BUILD"                          = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"             = "true"
    
    # HIPAA compliance settings
    "HIPAA_COMPLIANCE_ENABLED"                   = "true"
    "ENCRYPTION_ENABLED"                         = "true"
    "AUDIT_LOGGING_ENABLED"                      = "true"
    
    # Performance settings
    "WEBSITE_CONTENTOVERVNET"                    = "1"
    "WEBSITE_DNS_SERVER"                         = "168.63.129.16"
  }, var.additional_app_settings)
  
  tags = var.tags
}

# User-assigned managed identity for Functions
resource "azurerm_user_assigned_identity" "functions" {
  name                = "${var.project_name}-${var.environment}-functions-identity-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

# VNet integration for Functions
resource "azurerm_app_service_virtual_network_swift_connection" "functions" {
  count          = var.subnet_id != "" ? 1 : 0
  app_service_id = azurerm_linux_function_app.main.id
  subnet_id      = var.subnet_id
}

# Private endpoint for Function App
resource "azurerm_private_endpoint" "functions" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${azurerm_linux_function_app.main.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${azurerm_linux_function_app.main.name}-psc"
    private_connection_resource_id = azurerm_linux_function_app.main.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.functions[0].id]
  }

  tags = var.tags
}

# Private DNS zone for Function App
resource "azurerm_private_dns_zone" "functions" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.azurewebsites.net"
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "functions" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "${azurerm_linux_function_app.main.name}-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.functions[0].name
  virtual_network_id    = var.vnet_id
  
  tags = var.tags
}

# Key Vault access policy for Functions
resource "azurerm_key_vault_access_policy" "functions" {
  count        = var.key_vault_id != "" ? 1 : 0
  key_vault_id = var.key_vault_id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.functions.principal_id

  secret_permissions = [
    "Get",
    "List"
  ]

  key_permissions = [
    "Get",
    "List",
    "Decrypt",
    "Encrypt"
  ]
}

# Role assignments for Functions
resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  count                = var.storage_account_id != "" ? 1 : 0
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.functions.principal_id
}

resource "azurerm_role_assignment" "storage_queue_data_contributor" {
  count                = var.storage_account_id != "" ? 1 : 0
  scope                = var.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.functions.principal_id
}

# Diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "functions" {
  name                       = "${azurerm_linux_function_app.main.name}-diagnostics"
  target_resource_id         = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "FunctionAppLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Function App Slot for blue-green deployments
resource "azurerm_linux_function_app_slot" "staging" {
  count                      = var.enable_staging_slot ? 1 : 0
  name                       = "staging"
  function_app_id            = azurerm_linux_function_app.main.id
  storage_account_name       = var.storage_account_name
  storage_account_access_key = var.storage_account_access_key
  
  https_only = true
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.functions.id]
  }
  
  site_config {
    minimum_tls_version = "1.2"
    ftps_state         = "Disabled"
    
    application_stack {
      python_version = "3.11"
    }
    
    always_on = var.sku_name != "Y1"
    
    application_insights_key               = var.application_insights_key
    application_insights_connection_string = var.application_insights_connection_string
  }
  
  app_settings = azurerm_linux_function_app.main.app_settings
  
  tags = var.tags
}
