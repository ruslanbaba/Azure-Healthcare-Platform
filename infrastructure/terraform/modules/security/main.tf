# Security Module for Azure Healthcare Analytics Platform

# Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                       = "${var.project_name}-${var.environment}-kv-${var.unique_suffix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "premium"
  soft_delete_retention_days = 7
  purge_protection_enabled   = true
  
  # HIPAA compliance settings
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  
  # Network ACLs
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    
    # Allow access from specific subnets only
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }
  
  tags = merge(var.tags, {
    Purpose = "Security"
    HIPAA   = "Compliant"
  })
}

# Key Vault access policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = var.tenant_id
  object_id    = var.object_id

  key_permissions = [
    "Create",
    "Delete",
    "Get",
    "List",
    "Purge",
    "Recover",
    "Update",
    "GetRotationPolicy",
    "SetRotationPolicy"
  ]

  secret_permissions = [
    "Delete",
    "Get",
    "List",
    "Purge",
    "Recover",
    "Set"
  ]

  certificate_permissions = [
    "Create",
    "Delete",
    "Get",
    "Import",
    "List",
    "Purge",
    "Recover",
    "Update"
  ]
}

# User-assigned managed identity for Key Vault access
resource "azurerm_user_assigned_identity" "key_vault" {
  name                = "${var.project_name}-${var.environment}-kv-identity-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

# Key Vault access policy for managed identity
resource "azurerm_key_vault_access_policy" "managed_identity" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.key_vault.principal_id

  key_permissions = [
    "Get",
    "List",
    "Decrypt",
    "Encrypt"
  ]

  secret_permissions = [
    "Get",
    "List"
  ]

  certificate_permissions = [
    "Get",
    "List"
  ]
}

# Customer-managed key for encryption
resource "azurerm_key_vault_key" "encryption" {
  name         = "${var.project_name}-${var.environment}-cmk"
  key_vault_id = azurerm_key_vault.main.id
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

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }

    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }

  depends_on = [azurerm_key_vault_access_policy.current]
  
  tags = var.tags
}

# Generate secrets for different services
resource "random_password" "database_admin" {
  length  = 32
  special = true
}

resource "azurerm_key_vault_secret" "database_admin_password" {
  name         = "database-admin-password"
  value        = random_password.database_admin.result
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current]
  
  tags = var.tags
}

resource "random_password" "function_app_key" {
  length  = 64
  special = false
}

resource "azurerm_key_vault_secret" "function_app_key" {
  name         = "function-app-master-key"
  value        = random_password.function_app_key.result
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current]
  
  tags = var.tags
}

# SSL Certificate for custom domains (placeholder)
resource "azurerm_key_vault_certificate" "ssl" {
  name         = "${var.project_name}-ssl-cert"
  key_vault_id = azurerm_key_vault.main.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_actions {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject            = "CN=${var.project_name}-${var.environment}.com"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = [
          "${var.project_name}-${var.environment}.com",
          "*.${var.project_name}-${var.environment}.com"
        ]
      }
    }
  }

  depends_on = [azurerm_key_vault_access_policy.current]
  
  tags = var.tags
}

# Private endpoint for Key Vault
resource "azurerm_private_endpoint" "key_vault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${var.project_name}-${var.environment}-kv-pe-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.project_name}-${var.environment}-kv-psc"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault[0].id]
  }

  tags = var.tags
}

# Private DNS Zone for Key Vault
resource "azurerm_private_dns_zone" "key_vault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "${var.project_name}-${var.environment}-kv-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = var.vnet_id
  
  tags = var.tags
}

# Application Gateway for WAF protection
resource "azurerm_application_gateway" "main" {
  name                = "${var.project_name}-${var.environment}-agw-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
    
    disabled_rule_group {
      rule_group_name = "REQUEST-920-PROTOCOL-ENFORCEMENT"
      rules           = [920300, 920440]
    }
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = var.gateway_subnet_id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_port {
    name = "https-port"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-configuration"
    public_ip_address_id = var.gateway_public_ip_id
  }

  backend_address_pool {
    name = "backend-pool"
  }

  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-configuration"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "backend-http-settings"
    priority                   = 100
  }

  tags = var.tags
}
