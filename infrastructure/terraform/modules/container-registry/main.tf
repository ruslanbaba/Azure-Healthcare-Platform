# Container Registry Module for Azure Healthcare Analytics Platform

# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = "${replace(var.project_name, "-", "")}${var.environment}acr${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = var.admin_enabled
  
  # Network access control
  public_network_access_enabled = var.public_network_access_enabled
  
  # Geo-replication for Premium SKU
  dynamic "georeplications" {
    for_each = var.sku == "Premium" ? var.georeplications : []
    content {
      location                  = georeplications.value.location
      zone_redundancy_enabled   = georeplications.value.zone_redundancy_enabled
      regional_endpoint_enabled = georeplications.value.regional_endpoint_enabled
      tags                     = var.tags
    }
  }
  
  # Network rule set for Premium SKU
  dynamic "network_rule_set" {
    for_each = var.sku == "Premium" && length(var.allowed_subnet_ids) > 0 ? [1] : []
    content {
      default_action = "Deny"
      
      dynamic "virtual_network" {
        for_each = var.allowed_subnet_ids
        content {
          action    = "Allow"
          subnet_id = virtual_network.value
        }
      }
    }
  }
  
  # Encryption configuration
  encryption {
    enabled = true
  }
  
  # Trust policy
  trust_policy {
    enabled = true
  }
  
  # Retention policy
  retention_policy {
    enabled = true
    days    = var.retention_days
  }
  
  # Quarantine policy
  quarantine_policy {
    enabled = true
  }
  
  tags = merge(var.tags, {
    Purpose = "Container Registry"
    Security = "HIPAA-Compliant"
  })
}

# Private endpoint for Container Registry
resource "azurerm_private_endpoint" "acr" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${azurerm_container_registry.main.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${azurerm_container_registry.main.name}-psc"
    private_connection_resource_id = azurerm_container_registry.main.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr[0].id]
  }

  tags = var.tags
}

# Private DNS zone for Container Registry
resource "azurerm_private_dns_zone" "acr" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "${azurerm_container_registry.main.name}-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = var.vnet_id
  
  tags = var.tags
}

# Role assignment for AKS to pull from ACR
resource "azurerm_role_assignment" "acr_pull" {
  count                = var.aks_principal_id != "" ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = var.aks_principal_id
}

# Managed identity for ACR tasks
resource "azurerm_user_assigned_identity" "acr_tasks" {
  name                = "${azurerm_container_registry.main.name}-tasks-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

# Role assignment for ACR tasks identity
resource "azurerm_role_assignment" "acr_tasks_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.acr_tasks.principal_id
}

# ACR Task for automated image builds
resource "azurerm_container_registry_task" "build_task" {
  count                 = var.enable_build_tasks ? 1 : 0
  name                  = "healthcare-build-task"
  container_registry_id = azurerm_container_registry.main.id
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.acr_tasks.id]
  }
  
  platform {
    os           = "Linux"
    architecture = "amd64"
  }
  
  docker_step {
    dockerfile_path      = "Dockerfile"
    context_path         = "https://github.com/ruslanbaba/Azure-Healthcare-Platform.git"
    context_access_token = var.github_token
    image_names          = ["${azurerm_container_registry.main.login_server}/data-processor:{{.Run.ID}}"]
  }
  
  source_trigger {
    name           = "defaultSourceTriggerName"
    events         = ["commit"]
    repository_url = "https://github.com/ruslanbaba/Azure-Healthcare-Platform.git"
    source_type    = "Github"
    
    authentication {
      token      = var.github_token
      token_type = "PAT"
    }
    
    branch = "main"
  }
  
  tags = var.tags
}

# Diagnostic settings for Container Registry
resource "azurerm_monitor_diagnostic_setting" "acr" {
  name                       = "${azurerm_container_registry.main.name}-diagnostics"
  target_resource_id         = azurerm_container_registry.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Content trust signing key (for Premium SKU)
resource "azurerm_key_vault_key" "content_trust" {
  count        = var.sku == "Premium" ? 1 : 0
  name         = "${azurerm_container_registry.main.name}-content-trust"
  key_vault_id = var.key_vault_id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  tags = var.tags
}

# Webhook for security scanning
resource "azurerm_container_registry_webhook" "security_scan" {
  count               = var.enable_security_scanning ? 1 : 0
  name                = "securityscan"
  resource_group_name = var.resource_group_name
  registry_name       = azurerm_container_registry.main.name
  location            = var.location
  
  service_uri = var.security_scan_webhook_url
  status      = "enabled"
  scope       = "*"
  actions     = ["push"]
  
  custom_headers = {
    "Content-Type" = "application/json"
  }
  
  tags = var.tags
}
