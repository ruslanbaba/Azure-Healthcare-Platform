# Development Environment Configuration
environment           = "dev"
project_name          = "healthcare-analytics"
location              = "East US 2"
owner                 = "Healthcare Analytics Team"
cost_center           = "IT-Healthcare"

# Network Configuration
vnet_address_space = ["10.0.0.0/16"]

# AKS Configuration
aks_config = {
  kubernetes_version = "1.28"
  node_count_min     = 1
  node_count_max     = 5
  node_count_default = 2
  vm_size           = "Standard_D2s_v3"
  os_disk_size_gb   = 50
  enable_auto_scaling = true
  enable_rbac        = true
  network_plugin     = "azure"
  network_policy     = "calico"
}

# Data Lake Configuration
data_lake_config = {
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled          = true
  min_tls_version         = "TLS1_2"
  containers              = ["raw", "processed", "curated", "logs", "backups"]
}

# Function App Configuration
function_config = {
  runtime_version = "~4"
  runtime_stack   = "python"
  sku_name       = "Y1"  # Consumption plan for dev
}

# API Management Configuration
apim_config = {
  sku_name          = "Developer"
  publisher_name    = "Healthcare Analytics Dev"
  publisher_email   = "dev@healthcareanalytics.com"
}

# Security Configuration
enable_private_endpoints = false  # Reduced security for dev environment
backup_retention_days    = 7
log_retention_days       = 30

# Container Registry Configuration
acr_config = {
  sku                = "Basic"
  admin_enabled      = false
  public_network_access_enabled = true  # Allowed for dev
}
