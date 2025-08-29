output "storage_account_id" {
  description = "Storage account ID"
  value       = azurerm_storage_account.data_lake.id
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.data_lake.name
}

output "primary_dfs_endpoint" {
  description = "Primary DFS endpoint"
  value       = azurerm_storage_account.data_lake.primary_dfs_endpoint
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint"
  value       = azurerm_storage_account.data_lake.primary_blob_endpoint
}

output "containers" {
  description = "Created containers"
  value = {
    raw       = azurerm_storage_data_lake_gen2_filesystem.raw.name
    processed = azurerm_storage_data_lake_gen2_filesystem.processed.name
    curated   = azurerm_storage_data_lake_gen2_filesystem.curated.name
    logs      = azurerm_storage_data_lake_gen2_filesystem.logs.name
    backups   = azurerm_storage_data_lake_gen2_filesystem.backups.name
  }
}

output "backup_vault_id" {
  description = "Backup vault ID"
  value       = azurerm_data_protection_backup_vault.main.id
}
