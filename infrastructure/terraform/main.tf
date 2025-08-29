# Azure Healthcare Analytics Platform - Main Infrastructure
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
    # Backend configuration will be provided via backend config file
    # terraform init -backend-config=backend.conf
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}

# Data sources
data "azurerm_client_config" "current" {}

# Random suffix for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables
locals {
  environment    = var.environment
  project_name   = var.project_name
  location       = var.location
  common_tags = {
    Environment   = var.environment
    Project       = var.project_name
    ManagedBy     = "Terraform"
    Owner         = var.owner
    CostCenter    = var.cost_center
    Compliance    = "HIPAA"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
  }
  
  # Naming convention
  naming_prefix = "${local.project_name}-${local.environment}"
  unique_suffix = random_string.suffix.result
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${local.naming_prefix}-rg-${local.unique_suffix}"
  location = local.location
  tags     = local.common_tags
}

# Network Security Resource Group
resource "azurerm_resource_group" "security" {
  name     = "${local.naming_prefix}-security-rg-${local.unique_suffix}"
  location = local.location
  tags     = merge(local.common_tags, {
    Purpose = "Security"
  })
}

# Data Resource Group
resource "azurerm_resource_group" "data" {
  name     = "${local.naming_prefix}-data-rg-${local.unique_suffix}"
  location = local.location
  tags     = merge(local.common_tags, {
    Purpose = "Data"
  })
}

# Compute Resource Group
resource "azurerm_resource_group" "compute" {
  name     = "${local.naming_prefix}-compute-rg-${local.unique_suffix}"
  location = local.location
  tags     = merge(local.common_tags, {
    Purpose = "Compute"
  })
}

# Virtual Network
module "networking" {
  source = "./modules/networking"
  
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  environment        = local.environment
  project_name       = local.project_name
  unique_suffix      = local.unique_suffix
  tags              = local.common_tags
}

# Security and Key Vault
module "security" {
  source = "./modules/security"
  
  resource_group_name = azurerm_resource_group.security.name
  location           = azurerm_resource_group.security.location
  environment        = local.environment
  project_name       = local.project_name
  unique_suffix      = local.unique_suffix
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = data.azurerm_client_config.current.object_id
  tags              = local.common_tags
  
  depends_on = [module.networking]
}

# Data Lake and Storage
module "data_lake" {
  source = "./modules/data-lake"
  
  resource_group_name = azurerm_resource_group.data.name
  location           = azurerm_resource_group.data.location
  environment        = local.environment
  project_name       = local.project_name
  unique_suffix      = local.unique_suffix
  key_vault_id       = module.security.key_vault_id
  subnet_id          = module.networking.data_subnet_id
  tags              = local.common_tags
  
  depends_on = [module.security, module.networking]
}

# Azure Kubernetes Service
module "aks" {
  source = "./modules/aks"
  
  resource_group_name    = azurerm_resource_group.compute.name
  location              = azurerm_resource_group.compute.location
  environment           = local.environment
  project_name          = local.project_name
  unique_suffix         = local.unique_suffix
  subnet_id             = module.networking.aks_subnet_id
  key_vault_id          = module.security.key_vault_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                  = local.common_tags
  
  depends_on = [module.security, module.networking, module.monitoring]
}

# Azure Functions
module "functions" {
  source = "./modules/functions"
  
  resource_group_name = azurerm_resource_group.compute.name
  location           = azurerm_resource_group.compute.location
  environment        = local.environment
  project_name       = local.project_name
  unique_suffix      = local.unique_suffix
  storage_account_name = module.data_lake.storage_account_name
  key_vault_id       = module.security.key_vault_id
  subnet_id          = module.networking.functions_subnet_id
  tags              = local.common_tags
  
  depends_on = [module.data_lake, module.security, module.networking]
}

# API Management
module "api_management" {
  source = "./modules/api-management"
  
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  environment        = local.environment
  project_name       = local.project_name
  unique_suffix      = local.unique_suffix
  
  # Publisher configuration
  publisher_name  = "Healthcare Platform Admin"
  publisher_email = var.api_management_publisher_email
  
  # VNet integration
  virtual_network_type = "Internal"
  subnet_id           = module.networking.apim_subnet_id
  
  # Backend configuration
  backend_service_url = "https://backend.${var.domain_name}"
  key_vault_url      = module.security.key_vault_uri
  key_vault_id       = module.security.key_vault_id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  
  # Monitoring
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  
  tags = local.common_tags
  
  depends_on = [module.security, module.networking, module.monitoring]
}

# Observability and Monitoring
module "observability" {
  source = "./modules/observability"
  
  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  unique_suffix       = random_string.suffix.result
  
  # Network configuration
  virtual_network_id   = module.networking.virtual_network_id
  monitoring_subnet_id = module.networking.monitoring_subnet_id
  
  # Security configuration
  storage_encryption_key_id      = module.security.storage_encryption_key_id
  storage_managed_identity_id    = module.security.storage_managed_identity_id
  
  # Monitoring configuration
  log_analytics_retention_days      = 90
  application_insights_retention_days = 90
  log_analytics_daily_quota_gb      = 100
  application_insights_daily_cap_gb = 10
  
  # Alert configuration
  alert_email_receivers = [
    {
      name  = "healthcare-admin"
      email = var.admin_email
    },
    {
      name  = "platform-team"
      email = var.platform_team_email
    }
  ]
  
  # HIPAA compliance settings
  data_access_monitoring_enabled = true
  audit_log_retention_years      = 7
  data_export_monitoring_enabled = true
  encryption_monitoring_enabled  = true
  
  # Monitoring thresholds
  cpu_threshold_critical        = 90
  memory_threshold_critical     = 85
  disk_threshold_critical      = 80
  response_time_threshold_ms   = 5000
  error_rate_threshold         = 5
  failed_login_threshold       = 10
  suspicious_activity_threshold = 5
  
  tags = local.common_tags
  
  depends_on = [module.security, module.networking]
}

# Container Registry
module "container_registry" {
  source = "./modules/container-registry"
  
  resource_group_name = azurerm_resource_group.compute.name
  location           = azurerm_resource_group.compute.location
  environment        = local.environment
  project_name       = local.project_name
  unique_suffix      = local.unique_suffix
  key_vault_id       = module.security.key_vault_id
  tags              = local.common_tags
  
  depends_on = [module.security]
}
