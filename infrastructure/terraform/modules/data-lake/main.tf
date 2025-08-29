# Data Lake Module for Azure Healthcare Analytics Platform

# Storage Account for Data Lake Gen2
resource "azurerm_storage_account" "data_lake" {
  name                     = "${replace(var.project_name, "-", "")}${var.environment}dl${var.unique_suffix}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  account_kind             = "StorageV2"
  is_hns_enabled          = true  # Hierarchical namespace for Data Lake Gen2
  
  # HIPAA compliance settings
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  
  # Advanced threat protection
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled     = true
    change_feed_retention_in_days = 30
    last_access_time_enabled = true
    
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }
  
  # Network rules
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [var.subnet_id]
  }
  
  # Customer-managed encryption
  customer_managed_key {
    key_vault_key_id          = var.encryption_key_id
    user_assigned_identity_id = var.managed_identity_id
  }
  
  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }
  
  tags = merge(var.tags, {
    Purpose = "DataLake"
    DataClassification = "PHI"
    HIPAA = "Compliant"
  })
}

# Data Lake containers for different zones
resource "azurerm_storage_data_lake_gen2_filesystem" "raw" {
  name               = "raw"
  storage_account_id = azurerm_storage_account.data_lake.id
  
  properties = {
    "zone" = "bronze"
    "description" = "Raw healthcare data ingestion zone"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "processed" {
  name               = "processed"
  storage_account_id = azurerm_storage_account.data_lake.id
  
  properties = {
    "zone" = "silver"
    "description" = "Processed and cleansed healthcare data"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "curated" {
  name               = "curated"
  storage_account_id = azurerm_storage_account.data_lake.id
  
  properties = {
    "zone" = "gold"
    "description" = "Curated analytics-ready healthcare data"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "logs" {
  name               = "logs"
  storage_account_id = azurerm_storage_account.data_lake.id
  
  properties = {
    "zone" = "logs"
    "description" = "System and application logs"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "backups" {
  name               = "backups"
  storage_account_id = azurerm_storage_account.data_lake.id
  
  properties = {
    "zone" = "backup"
    "description" = "Data backups and disaster recovery"
  }
}

# Management policy for lifecycle management
resource "azurerm_storage_management_policy" "data_lake" {
  storage_account_id = azurerm_storage_account.data_lake.id

  rule {
    name    = "raw-data-lifecycle"
    enabled = true

    filters {
      prefix_match = ["raw/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 2555  # 7 years HIPAA retention
      }
      
      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }
      
      version {
        delete_after_days_since_creation = 90
      }
    }
  }

  rule {
    name    = "processed-data-lifecycle"
    enabled = true

    filters {
      prefix_match = ["processed/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 90
        tier_to_archive_after_days_since_modification_greater_than = 365
        delete_after_days_since_modification_greater_than          = 2555  # 7 years HIPAA retention
      }
    }
  }

  rule {
    name    = "logs-lifecycle"
    enabled = true

    filters {
      prefix_match = ["logs/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 7
        tier_to_archive_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than = 365
      }
    }
  }
}

# Private endpoint for storage account
resource "azurerm_private_endpoint" "storage_blob" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${azurerm_storage_account.data_lake.name}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${azurerm_storage_account.data_lake.name}-blob-psc"
    private_connection_resource_id = azurerm_storage_account.data_lake.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob[0].id]
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "storage_dfs" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${azurerm_storage_account.data_lake.name}-dfs-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${azurerm_storage_account.data_lake.name}-dfs-psc"
    private_connection_resource_id = azurerm_storage_account.data_lake.id
    subresource_names              = ["dfs"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_dfs[0].id]
  }

  tags = var.tags
}

# Private DNS zones
resource "azurerm_private_dns_zone" "storage_blob" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

resource "azurerm_private_dns_zone" "storage_dfs" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "${azurerm_storage_account.data_lake.name}-blob-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob[0].name
  virtual_network_id    = var.vnet_id
  
  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_dfs" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "${azurerm_storage_account.data_lake.name}-dfs-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_dfs[0].name
  virtual_network_id    = var.vnet_id
  
  tags = var.tags
}

# Data Lake role assignments
resource "azurerm_role_assignment" "data_lake_contributor" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.aks_principal_id
}

resource "azurerm_role_assignment" "data_lake_reader" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.functions_principal_id
}

# Backup vault for storage account
resource "azurerm_data_protection_backup_vault" "main" {
  name                = "${var.project_name}-${var.environment}-bv-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  datastore_type      = "VaultStore"
  redundancy          = "ZoneRedundant"
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}

# Backup policy for storage account
resource "azurerm_data_protection_backup_policy_blob_storage" "main" {
  name               = "${var.project_name}-${var.environment}-backup-policy"
  vault_id           = azurerm_data_protection_backup_vault.main.id
  retention_duration = "P${var.backup_retention_days}D"
  
  backup_repeating_time_intervals = ["R/2024-01-01T02:00:00+00:00/P1D"]
}

# Backup instance for storage account
resource "azurerm_data_protection_backup_instance_blob_storage" "main" {
  name               = "${azurerm_storage_account.data_lake.name}-backup"
  vault_id           = azurerm_data_protection_backup_vault.main.id
  location           = var.location
  storage_account_id = azurerm_storage_account.data_lake.id
  backup_policy_id   = azurerm_data_protection_backup_policy_blob_storage.main.id
}
