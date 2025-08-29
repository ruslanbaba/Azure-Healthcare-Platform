output "function_app_id" {
  description = "Function App ID"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_name" {
  description = "Function App name"
  value       = azurerm_linux_function_app.main.name
}

output "default_hostname" {
  description = "Function App default hostname"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "identity_principal_id" {
  description = "Function App identity principal ID"
  value       = azurerm_user_assigned_identity.functions.principal_id
}

output "identity_client_id" {
  description = "Function App identity client ID"
  value       = azurerm_user_assigned_identity.functions.client_id
}

output "outbound_ip_addresses" {
  description = "Function App outbound IP addresses"
  value       = azurerm_linux_function_app.main.outbound_ip_addresses
}

output "possible_outbound_ip_addresses" {
  description = "Function App possible outbound IP addresses"
  value       = azurerm_linux_function_app.main.possible_outbound_ip_addresses
}
