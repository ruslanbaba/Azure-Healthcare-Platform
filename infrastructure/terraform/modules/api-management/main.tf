# API Management Module for Azure Healthcare Analytics Platform

# API Management Service
resource "azurerm_api_management" "main" {
  name                = "${var.project_name}-${var.environment}-apim-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name           = var.sku_name
  
  # Identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Security protocols
  protocols {
    enable_http2 = true
  }
  
  security {
    enable_backend_ssl30                                = false
    enable_backend_tls10                                = false
    enable_backend_tls11                                = false
    enable_frontend_ssl30                               = false
    enable_frontend_tls10                               = false
    enable_frontend_tls11                               = false
    tls_ecdhe_ecdsa_with_aes256_cbc_sha_ciphers_enabled = false
    tls_ecdhe_ecdsa_with_aes128_cbc_sha_ciphers_enabled = false
    tls_ecdhe_rsa_with_aes256_cbc_sha_ciphers_enabled   = false
    tls_ecdhe_rsa_with_aes128_cbc_sha_ciphers_enabled   = false
    tls_rsa_with_aes128_gcm_sha256_ciphers_enabled      = false
    tls_rsa_with_aes256_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes128_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes256_cbc_sha_ciphers_enabled         = false
    tls_rsa_with_aes128_cbc_sha_ciphers_enabled         = false
    triple_des_ciphers_enabled                          = false
  }
  
  # Virtual network configuration for internal mode
  virtual_network_type = var.virtual_network_type
  
  dynamic "virtual_network_configuration" {
    for_each = var.virtual_network_type == "Internal" ? [1] : []
    content {
      subnet_id = var.subnet_id
    }
  }
  
  tags = merge(var.tags, {
    Purpose = "API Gateway"
    Security = "HIPAA-Compliant"
  })
}

# API Management Custom Domain
resource "azurerm_api_management_custom_domain" "main" {
  count             = var.custom_domain_certificate_id != "" ? 1 : 0
  api_management_id = azurerm_api_management.main.id

  gateway {
    host_name                    = var.gateway_hostname
    key_vault_id                = var.custom_domain_certificate_id
    negotiate_client_certificate = false
  }
  
  developer_portal {
    host_name    = var.developer_portal_hostname
    key_vault_id = var.custom_domain_certificate_id
  }
  
  management {
    host_name    = var.management_hostname
    key_vault_id = var.custom_domain_certificate_id
  }
}

# Healthcare API
resource "azurerm_api_management_api" "healthcare" {
  name                  = "healthcare-api"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "Healthcare Analytics API"
  path                  = "healthcare"
  protocols             = ["https"]
  service_url          = var.backend_service_url
  subscription_required = true
  
  description = "HIPAA-compliant Healthcare Analytics API"
  
  import {
    content_format = "openapi+json"
    content_value = jsonencode({
      openapi = "3.0.0"
      info = {
        title   = "Healthcare Analytics API"
        version = "1.0.0"
        description = "HIPAA-compliant API for healthcare data analytics"
      }
      servers = [
        {
          url = "https://${azurerm_api_management.main.gateway_url}/healthcare"
        }
      ]
      paths = {
        "/patients" = {
          get = {
            summary = "Get patient data"
            operationId = "getPatients"
            responses = {
              "200" = {
                description = "Successful response"
                content = {
                  "application/json" = {
                    schema = {
                      type = "array"
                      items = {
                        type = "object"
                        properties = {
                          id = { type = "string" }
                          name = { type = "string" }
                          age = { type = "integer" }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        "/analytics" = {
          get = {
            summary = "Get analytics data"
            operationId = "getAnalytics"
            responses = {
              "200" = {
                description = "Successful response"
              }
            }
          }
        }
      }
    })
  }
}

# API Management Product
resource "azurerm_api_management_product" "healthcare" {
  product_id            = "healthcare-platform"
  api_management_name   = azurerm_api_management.main.name
  resource_group_name   = var.resource_group_name
  display_name          = "Healthcare Platform"
  description           = "Healthcare Analytics Platform APIs"
  terms                 = "Terms and conditions for Healthcare Platform usage"
  subscription_required = true
  approval_required     = true
  published             = true
  
  subscriptions_limit = 100
}

# Product API Association
resource "azurerm_api_management_product_api" "healthcare" {
  api_name            = azurerm_api_management_api.healthcare.name
  product_id          = azurerm_api_management_product.healthcare.product_id
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
}

# Named Values for configuration
resource "azurerm_api_management_named_value" "backend_url" {
  name                = "backend-url"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  display_name        = "Backend URL"
  value               = var.backend_service_url
}

resource "azurerm_api_management_named_value" "key_vault_url" {
  name                = "key-vault-url"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  display_name        = "Key Vault URL"
  value               = var.key_vault_url
  secret              = true
}

# Global Policy for all APIs
resource "azurerm_api_management_api_policy" "healthcare_global" {
  api_name            = azurerm_api_management_api.healthcare.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name

  xml_content = <<XML
<policies>
  <inbound>
    <!-- CORS policy -->
    <cors allow-credentials="false">
      <allowed-origins>
        <origin>https://${var.allowed_origin}</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>PUT</method>
        <method>DELETE</method>
      </allowed-methods>
      <allowed-headers>
        <header>*</header>
      </allowed-headers>
    </cors>
    
    <!-- Rate limiting -->
    <rate-limit-by-key calls="1000" renewal-period="3600" counter-key="@(context.Request.IpAddress)" />
    
    <!-- Authentication validation -->
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <openid-config url="https://login.microsoftonline.com/${var.tenant_id}/v2.0/.well-known/openid_configuration" />
      <audiences>
        <audience>api://healthcare-platform</audience>
      </audiences>
    </validate-jwt>
    
    <!-- Request logging for audit -->
    <log-to-eventhub logger-id="healthcare-audit-logger" partition-id="0">
      @{
        return new JObject(
          new JProperty("timestamp", DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")),
          new JProperty("request_id", context.RequestId),
          new JProperty("ip_address", context.Request.IpAddress),
          new JProperty("method", context.Request.Method),
          new JProperty("url", context.Request.Url.ToString()),
          new JProperty("user_id", context.User?.Id),
          new JProperty("subscription_id", context.Subscription?.Id)
        ).ToString();
      }
    </log-to-eventhub>
    
    <!-- Set backend URL -->
    <set-backend-service base-url="{{backend-url}}" />
  </inbound>
  
  <backend>
    <base />
  </backend>
  
  <outbound>
    <!-- Remove sensitive headers -->
    <set-header name="X-Powered-By" exists-action="delete" />
    <set-header name="Server" exists-action="delete" />
    
    <!-- Add security headers -->
    <set-header name="X-Content-Type-Options" exists-action="override">
      <value>nosniff</value>
    </set-header>
    <set-header name="X-Frame-Options" exists-action="override">
      <value>DENY</value>
    </set-header>
    <set-header name="X-XSS-Protection" exists-action="override">
      <value>1; mode=block</value>
    </set-header>
    <set-header name="Strict-Transport-Security" exists-action="override">
      <value>max-age=31536000; includeSubDomains</value>
    </set-header>
    
    <base />
  </outbound>
  
  <on-error>
    <!-- Error logging -->
    <log-to-eventhub logger-id="healthcare-error-logger" partition-id="1">
      @{
        return new JObject(
          new JProperty("timestamp", DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")),
          new JProperty("request_id", context.RequestId),
          new JProperty("error", context.LastError.Reason),
          new JProperty("message", context.LastError.Message)
        ).ToString();
      }
    </log-to-eventhub>
    
    <base />
  </on-error>
</policies>
XML
}

# Logger for audit trails
resource "azurerm_api_management_logger" "audit" {
  count               = var.eventhub_connection_string != "" ? 1 : 0
  name                = "healthcare-audit-logger"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name

  eventhub {
    name              = var.audit_eventhub_name
    connection_string = var.eventhub_connection_string
  }
}

# Logger for errors
resource "azurerm_api_management_logger" "error" {
  count               = var.eventhub_connection_string != "" ? 1 : 0
  name                = "healthcare-error-logger"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name

  eventhub {
    name              = var.error_eventhub_name
    connection_string = var.eventhub_connection_string
  }
}

# Diagnostic settings for API Management
resource "azurerm_monitor_diagnostic_setting" "apim" {
  name                       = "${azurerm_api_management.main.name}-diagnostics"
  target_resource_id         = azurerm_api_management.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "GatewayLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Key Vault access policy for API Management
resource "azurerm_key_vault_access_policy" "apim" {
  count        = var.key_vault_id != "" ? 1 : 0
  key_vault_id = var.key_vault_id
  tenant_id    = var.tenant_id
  object_id    = azurerm_api_management.main.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]

  certificate_permissions = [
    "Get",
    "List"
  ]
}
