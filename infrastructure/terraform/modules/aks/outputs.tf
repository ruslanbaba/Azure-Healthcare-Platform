output "cluster_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "AKS cluster FQDN"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "node_resource_group" {
  description = "AKS node resource group"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "kubelet_identity" {
  description = "AKS kubelet identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "workload_identity_client_id" {
  description = "Workload identity client ID"
  value       = azurerm_user_assigned_identity.workload.client_id
}

output "workload_identity_principal_id" {
  description = "Workload identity principal ID"
  value       = azurerm_user_assigned_identity.workload.principal_id
}

output "managed_identity_principal_id" {
  description = "AKS managed identity principal ID"
  value       = azurerm_user_assigned_identity.aks.principal_id
}
