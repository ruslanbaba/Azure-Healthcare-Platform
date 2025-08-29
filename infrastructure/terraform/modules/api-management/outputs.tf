# API Management Module Outputs

output "api_management_id" {
  description = "ID of the API Management service"
  value       = azurerm_api_management.main.id
}

output "api_management_name" {
  description = "Name of the API Management service"
  value       = azurerm_api_management.main.name
}

output "gateway_url" {
  description = "Gateway URL of the API Management service"
  value       = azurerm_api_management.main.gateway_url
}

output "management_api_url" {
  description = "Management API URL of the API Management service"
  value       = azurerm_api_management.main.management_api_url
}

output "developer_portal_url" {
  description = "Developer portal URL of the API Management service"
  value       = azurerm_api_management.main.developer_portal_url
}

output "scm_url" {
  description = "SCM URL of the API Management service"
  value       = azurerm_api_management.main.scm_url
}

output "public_ip_addresses" {
  description = "Public IP addresses of the API Management service"
  value       = azurerm_api_management.main.public_ip_addresses
}

output "private_ip_addresses" {
  description = "Private IP addresses of the API Management service"
  value       = azurerm_api_management.main.private_ip_addresses
}

output "principal_id" {
  description = "Principal ID of the managed identity"
  value       = azurerm_api_management.main.identity[0].principal_id
}

output "tenant_id" {
  description = "Tenant ID of the managed identity"
  value       = azurerm_api_management.main.identity[0].tenant_id
}

output "healthcare_api_id" {
  description = "ID of the Healthcare API"
  value       = azurerm_api_management_api.healthcare.id
}

output "healthcare_api_name" {
  description = "Name of the Healthcare API"
  value       = azurerm_api_management_api.healthcare.name
}

output "healthcare_product_id" {
  description = "ID of the Healthcare product"
  value       = azurerm_api_management_product.healthcare.id
}

output "healthcare_product_name" {
  description = "Name of the Healthcare product"
  value       = azurerm_api_management_product.healthcare.display_name
}
