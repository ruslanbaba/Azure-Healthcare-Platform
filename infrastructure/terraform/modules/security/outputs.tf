output "key_vault_id" {
  description = "Key Vault ID"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}

output "managed_identity_id" {
  description = "Managed identity ID for Key Vault access"
  value       = azurerm_user_assigned_identity.key_vault.id
}

output "managed_identity_principal_id" {
  description = "Managed identity principal ID"
  value       = azurerm_user_assigned_identity.key_vault.principal_id
}

output "managed_identity_client_id" {
  description = "Managed identity client ID"
  value       = azurerm_user_assigned_identity.key_vault.client_id
}

output "encryption_key_id" {
  description = "Customer-managed encryption key ID"
  value       = azurerm_key_vault_key.encryption.id
}

output "application_gateway_id" {
  description = "Application Gateway ID"
  value       = azurerm_application_gateway.main.id
}

output "application_gateway_name" {
  description = "Application Gateway name"
  value       = azurerm_application_gateway.main.name
}
