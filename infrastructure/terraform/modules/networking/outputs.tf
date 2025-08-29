output "vnet_id" {
  description = "Virtual network ID"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual network name"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "AKS subnet ID"
  value       = azurerm_subnet.aks.id
}

output "data_subnet_id" {
  description = "Data subnet ID"
  value       = azurerm_subnet.data.id
}

output "functions_subnet_id" {
  description = "Functions subnet ID"
  value       = azurerm_subnet.functions.id
}

output "apim_subnet_id" {
  description = "API Management subnet ID"
  value       = azurerm_subnet.apim.id
}

output "gateway_subnet_id" {
  description = "Application Gateway subnet ID"
  value       = azurerm_subnet.gateway.id
}

output "private_endpoints_subnet_id" {
  description = "Private endpoints subnet ID"
  value       = azurerm_subnet.private_endpoints.id
}

output "gateway_public_ip_id" {
  description = "Application Gateway public IP ID"
  value       = azurerm_public_ip.gateway.id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = azurerm_nat_gateway.main.id
}
