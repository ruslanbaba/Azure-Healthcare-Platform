# Output Values for Azure Healthcare Analytics Platform

# Resource Groups
output "resource_groups" {
  description = "Created resource groups"
  value = {
    main     = azurerm_resource_group.main.name
    security = azurerm_resource_group.security.name
    data     = azurerm_resource_group.data.name
    compute  = azurerm_resource_group.compute.name
  }
}

# Networking
output "networking" {
  description = "Networking configuration"
  value = {
    vnet_id           = module.networking.vnet_id
    vnet_name         = module.networking.vnet_name
    aks_subnet_id     = module.networking.aks_subnet_id
    data_subnet_id    = module.networking.data_subnet_id
    functions_subnet_id = module.networking.functions_subnet_id
    apim_subnet_id    = module.networking.apim_subnet_id
  }
  sensitive = false
}

# Security
output "security" {
  description = "Security services"
  value = {
    key_vault_id   = module.security.key_vault_id
    key_vault_name = module.security.key_vault_name
    key_vault_uri  = module.security.key_vault_uri
  }
  sensitive = false
}

# Data Lake
output "data_lake" {
  description = "Data Lake configuration"
  value = {
    storage_account_name = module.data_lake.storage_account_name
    storage_account_id   = module.data_lake.storage_account_id
    primary_dfs_endpoint = module.data_lake.primary_dfs_endpoint
    containers          = module.data_lake.containers
  }
  sensitive = false
}

# AKS
output "aks" {
  description = "AKS cluster information"
  value = {
    cluster_name          = module.aks.cluster_name
    cluster_id           = module.aks.cluster_id
    cluster_fqdn         = module.aks.cluster_fqdn
    node_resource_group  = module.aks.node_resource_group
    kubelet_identity     = module.aks.kubelet_identity
  }
  sensitive = false
}

# Container Registry
output "container_registry" {
  description = "Container Registry information"
  value = {
    name         = module.container_registry.name
    login_server = module.container_registry.login_server
    id          = module.container_registry.id
  }
  sensitive = false
}

# Azure Functions
output "functions" {
  description = "Azure Functions information"
  value = {
    function_app_name = module.functions.function_app_name
    function_app_id   = module.functions.function_app_id
    default_hostname  = module.functions.default_hostname
  }
  sensitive = false
}

# API Management
output "api_management" {
  description = "API Management information"
  value = {
    name           = module.api_management.name
    gateway_url    = module.api_management.gateway_url
    management_url = module.api_management.management_url
    portal_url     = module.api_management.portal_url
  }
  sensitive = false
}

# Monitoring
output "monitoring" {
  description = "Monitoring services"
  value = {
    log_analytics_workspace_id   = module.monitoring.log_analytics_workspace_id
    log_analytics_workspace_name = module.monitoring.log_analytics_workspace_name
    application_insights_id      = module.monitoring.application_insights_id
    application_insights_key     = module.monitoring.application_insights_instrumentation_key
  }
  sensitive = true
}

# Connection Information
output "connection_info" {
  description = "Connection information for applications"
  value = {
    aks_get_credentials_command = "az aks get-credentials --resource-group ${azurerm_resource_group.compute.name} --name ${module.aks.cluster_name}"
    acr_login_command          = "az acr login --name ${module.container_registry.name}"
  }
  sensitive = false
}

# Environment Configuration
output "environment_config" {
  description = "Environment configuration for CI/CD"
  value = {
    environment      = local.environment
    location        = local.location
    resource_suffix = local.unique_suffix
    tags           = local.common_tags
  }
  sensitive = false
}
