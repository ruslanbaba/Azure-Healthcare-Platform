output "id" {
  description = "Container Registry ID"
  value       = azurerm_container_registry.main.id
}

output "name" {
  description = "Container Registry name"
  value       = azurerm_container_registry.main.name
}

output "login_server" {
  description = "Container Registry login server"
  value       = azurerm_container_registry.main.login_server
}

output "admin_username" {
  description = "Container Registry admin username"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "admin_password" {
  description = "Container Registry admin password"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

output "identity_principal_id" {
  description = "Container Registry identity principal ID"
  value       = azurerm_user_assigned_identity.acr_tasks.principal_id
}

output "identity_client_id" {
  description = "Container Registry identity client ID"
  value       = azurerm_user_assigned_identity.acr_tasks.client_id
}
