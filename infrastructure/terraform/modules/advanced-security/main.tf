# Advanced Security & Zero-Trust Architecture Enhancement
# Azure Healthcare Platform - Enhanced Security Module

# Azure Sentinel (Security Information and Event Management)
resource "azurerm_log_analytics_solution" "sentinel" {
  solution_name         = "SecurityInsights"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = var.log_analytics_workspace_id
  workspace_name        = var.log_analytics_workspace_name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/SecurityInsights"
  }

  tags = merge(var.tags, {
    Purpose = "SecurityMonitoring"
    Compliance = "HIPAA"
  })
}

# Azure Security Center Enhanced
resource "azurerm_security_center_subscription_pricing" "healthcare_security" {
  tier          = "Standard"
  resource_type = "VirtualMachines"
}

resource "azurerm_security_center_subscription_pricing" "kubernetes_security" {
  tier          = "Standard"
  resource_type = "KubernetesService"
}

resource "azurerm_security_center_subscription_pricing" "container_registry_security" {
  tier          = "Standard"
  resource_type = "ContainerRegistry"
}

resource "azurerm_security_center_subscription_pricing" "storage_security" {
  tier          = "Standard"
  resource_type = "StorageAccounts"
}

resource "azurerm_security_center_subscription_pricing" "sql_security" {
  tier          = "Standard"
  resource_type = "SqlServers"
}

# Azure DDoS Protection Plan
resource "azurerm_network_ddos_protection_plan" "healthcare_ddos" {
  name                = "${var.project_name}-${var.environment}-ddos-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    Purpose = "DDoSProtection"
    Component = "Security"
  })
}

# Azure Firewall Premium for Advanced Threat Protection
resource "azurerm_firewall" "healthcare_firewall" {
  name                = "${var.project_name}-${var.environment}-fw-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name           = "AZFW_VNet"
  sku_tier           = "Premium"
  firewall_policy_id = azurerm_firewall_policy.healthcare_policy.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = var.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.firewall_pip.id
  }

  tags = merge(var.tags, {
    Purpose = "AdvancedThreatProtection"
    Component = "Firewall"
  })
}

# Firewall Premium Policy with IDPS
resource "azurerm_firewall_policy" "healthcare_policy" {
  name                     = "${var.project_name}-${var.environment}-fw-policy-${var.unique_suffix}"
  resource_group_name      = var.resource_group_name
  location                = var.location
  sku                     = "Premium"
  threat_intelligence_mode = "Alert"

  # Advanced threat protection
  intrusion_detection {
    mode = "Alert"
    signature_overrides {
      id    = "2008983"
      state = "Alert"
    }
    traffic_bypass {
      name        = "healthcare-bypass"
      protocol    = "TCP"
      description = "Healthcare specific bypass"
      destination_ports = ["443", "80"]
    }
  }

  # TLS inspection
  tls_certificate {
    key_vault_secret_id = var.tls_certificate_key_vault_id
    name               = "healthcare-tls-cert"
  }

  tags = var.tags
}

# Public IP for Firewall
resource "azurerm_public_ip" "firewall_pip" {
  name                = "${var.project_name}-${var.environment}-fw-pip-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                = "Standard"
  zones              = ["1", "2", "3"]

  tags = var.tags
}

# Azure Application Gateway v2 with WAF
resource "azurerm_application_gateway" "healthcare_agw" {
  name                = "${var.project_name}-${var.environment}-agw-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  # Autoscaling
  autoscale_configuration {
    min_capacity = 2
    max_capacity = 10
  }

  gateway_ip_configuration {
    name      = "agw-ip-configuration"
    subnet_id = var.agw_subnet_id
  }

  frontend_port {
    name = "frontend-port-443"
    port = 443
  }

  frontend_port {
    name = "frontend-port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.agw_pip.id
  }

  backend_address_pool {
    name = "healthcare-backend-pool"
  }

  backend_http_settings {
    name                  = "healthcare-backend-settings"
    cookie_based_affinity = "Disabled"
    path                  = "/health"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60

    # Health probe
    probe_name = "healthcare-health-probe"
  }

  http_listener {
    name                           = "healthcare-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "frontend-port-443"
    protocol                       = "Https"
    ssl_certificate_name           = "healthcare-ssl-cert"
  }

  request_routing_rule {
    name                       = "healthcare-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "healthcare-listener"
    backend_address_pool_name  = "healthcare-backend-pool"
    backend_http_settings_name = "healthcare-backend-settings"
    priority                   = 100
  }

  # SSL Certificate
  ssl_certificate {
    name     = "healthcare-ssl-cert"
    key_vault_secret_id = var.ssl_certificate_key_vault_id
  }

  # WAF Configuration
  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"

    # Healthcare-specific exclusions
    exclusion {
      match_variable          = "RequestHeaderNames"
      selector_match_operator = "Equals"
      selector                = "x-fhir-authorization"
    }

    exclusion {
      match_variable          = "RequestCookieNames"
      selector_match_operator = "Equals"
      selector                = "healthcare-session"
    }
  }

  # Health Probe
  probe {
    name                                      = "healthcare-health-probe"
    protocol                                  = "Http"
    path                                      = "/health"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
      body        = "OK"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agw_identity.id]
  }

  tags = merge(var.tags, {
    Purpose = "WAF"
    Component = "ApplicationGateway"
  })
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "agw_pip" {
  name                = "${var.project_name}-${var.environment}-agw-pip-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                = "Standard"
  zones              = ["1", "2", "3"]

  tags = var.tags
}

# User Assigned Identity for Application Gateway
resource "azurerm_user_assigned_identity" "agw_identity" {
  name                = "${var.project_name}-${var.environment}-agw-identity-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Azure Private DNS Resolver for Enhanced Resolution
resource "azurerm_private_dns_resolver" "healthcare_resolver" {
  name                = "${var.project_name}-${var.environment}-dns-resolver-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_network_id  = var.vnet_id

  tags = merge(var.tags, {
    Purpose = "DNSResolution"
    Component = "PrivateDNS"
  })
}

# Inbound DNS Resolver Endpoint
resource "azurerm_private_dns_resolver_inbound_endpoint" "healthcare_inbound" {
  name                    = "healthcare-inbound-endpoint"
  private_dns_resolver_id = azurerm_private_dns_resolver.healthcare_resolver.id
  location                = var.location

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = var.dns_inbound_subnet_id
  }

  tags = var.tags
}

# Outbound DNS Resolver Endpoint
resource "azurerm_private_dns_resolver_outbound_endpoint" "healthcare_outbound" {
  name                    = "healthcare-outbound-endpoint"
  private_dns_resolver_id = azurerm_private_dns_resolver.healthcare_resolver.id
  location                = var.location
  subnet_id               = var.dns_outbound_subnet_id

  tags = var.tags
}

# Azure Bastion for Secure Remote Access
resource "azurerm_bastion_host" "healthcare_bastion" {
  name                = "${var.project_name}-${var.environment}-bastion-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                = "Standard"
  scale_units        = 2

  # Advanced features
  copy_paste_enabled     = false
  file_copy_enabled      = false
  ip_connect_enabled     = true
  shareable_link_enabled = false
  tunneling_enabled      = true

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = var.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
  }

  tags = merge(var.tags, {
    Purpose = "SecureRemoteAccess"
    Component = "Bastion"
  })
}

# Public IP for Bastion
resource "azurerm_public_ip" "bastion_pip" {
  name                = "${var.project_name}-${var.environment}-bastion-pip-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                = "Standard"

  tags = var.tags
}

# Azure Key Vault Access Policy for Enhanced Security
resource "azurerm_key_vault_access_policy" "security_access" {
  key_vault_id = var.key_vault_id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.agw_identity.principal_id

  key_permissions = [
    "Get",
    "List",
    "Decrypt",
  ]

  secret_permissions = [
    "Get",
    "List",
  ]

  certificate_permissions = [
    "Get",
    "List",
  ]
}
