# Production Environment Configuration
environment           = "prod"
project_name          = "healthcare-analytics"
location              = "East US 2"
owner                 = "Healthcare Analytics Team"
cost_center           = "IT-Healthcare"

# Network Configuration
vnet_address_space = ["10.0.0.0/16"]

# AKS Configuration
aks_config = {
  kubernetes_version = "1.28"
  node_count_min     = 3
  node_count_max     = 20
  node_count_default = 5
  vm_size           = "Standard_D8s_v3"
  os_disk_size_gb   = 100
  enable_auto_scaling = true
  enable_rbac        = true
  network_plugin     = "azure"
  network_policy     = "calico"
}

# Data Lake Configuration
data_lake_config = {
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  is_hns_enabled          = true
  min_tls_version         = "TLS1_2"
  containers              = ["raw", "processed", "curated", "logs", "backups"]
}

# Function App Configuration
function_config = {
  runtime_version = "~4"
  runtime_stack   = "python"
  sku_name       = "EP2"
}

# API Management Configuration
apim_config = {
  sku_name          = "Premium"
  publisher_name    = "Healthcare Analytics"
  publisher_email   = "admin@healthcareanalytics.com"
}

# Security Configuration
enable_private_endpoints = true
backup_retention_days    = 2555  # 7 years for HIPAA compliance
log_retention_days       = 365

# Container Registry Configuration
acr_config = {
  sku                = "Premium"
  admin_enabled      = false
  public_network_access_enabled = false
}
