# AKS Module for Azure Healthcare Analytics Platform

# User-assigned managed identity for AKS
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.project_name}-${var.environment}-aks-identity-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.project_name}-${var.environment}-aks-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.project_name}-${var.environment}-aks"
  kubernetes_version  = var.kubernetes_version
  
  # Security and compliance settings
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false
  role_based_access_control_enabled   = true
  local_account_disabled              = true
  
  # Identity configuration
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }
  
  # Default node pool
  default_node_pool {
    name                         = "system"
    vm_size                      = var.vm_size
    node_count                   = var.node_count_default
    min_count                    = var.node_count_min
    max_count                    = var.node_count_max
    enable_auto_scaling          = var.enable_auto_scaling
    vnet_subnet_id              = var.subnet_id
    os_disk_size_gb             = var.os_disk_size_gb
    os_disk_type                = "Managed"
    only_critical_addons_enabled = true
    
    # Security settings
    fips_enabled = true
    
    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
      "nodepoolos"    = "linux"
    }
    
    tags = merge(var.tags, {
      "nodepool-type" = "system"
    })
  }
  
  # Network configuration
  network_profile {
    network_plugin     = var.network_plugin
    network_policy     = var.network_policy
    dns_service_ip     = "10.100.0.10"
    service_cidr       = "10.100.0.0/16"
    outbound_type      = "userDefinedRouting"
  }
  
  # Azure AD integration
  azure_active_directory_role_based_access_control {
    managed                = true
    tenant_id              = var.tenant_id
    admin_group_object_ids = var.admin_group_object_ids
    azure_rbac_enabled     = true
  }
  
  # Monitoring and logging
  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }
  
  # Azure Policy Add-on
  azure_policy_enabled = true
  
  # Microsoft Defender
  microsoft_defender {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }
  
  # HTTP Application Routing (disabled for security)
  http_application_routing_enabled = false
  
  # Open Service Mesh
  open_service_mesh_enabled = true
  
  # Key Vault Secrets Provider
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }
  
  # Workload Identity
  workload_identity_enabled = true
  oidc_issuer_enabled      = true
  
  # Image Cleaner
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48
  
  # Maintenance window
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [2, 3, 4]
    }
  }
  
  # Node resource group
  node_resource_group = "${var.resource_group_name}-aks-nodes"
  
  tags = merge(var.tags, {
    Purpose = "Container Orchestration"
  })
}

# Additional node pool for application workloads
resource "azurerm_kubernetes_cluster_node_pool" "application" {
  name                  = "apps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size              = "Standard_D8s_v3"
  node_count           = 2
  min_count            = 1
  max_count            = 20
  enable_auto_scaling  = true
  vnet_subnet_id       = var.subnet_id
  os_disk_size_gb      = 100
  os_disk_type         = "Managed"
  
  # Taints for application workloads
  node_taints = ["workload=application:NoSchedule"]
  
  node_labels = {
    "nodepool-type" = "application"
    "environment"   = var.environment
    "workload"      = "application"
  }
  
  tags = merge(var.tags, {
    "nodepool-type" = "application"
  })
}

# Role assignments for AKS managed identity
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_managed_identity_operator" {
  scope                = azurerm_user_assigned_identity.aks.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Role assignment for Container Registry access
resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = var.container_registry_id != "" ? 1 : 0
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# Diagnostic settings for AKS
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "${azurerm_kubernetes_cluster.main.name}-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "kube-apiserver"
  }
  
  enabled_log {
    category = "kube-audit"
  }
  
  enabled_log {
    category = "kube-audit-admin"
  }
  
  enabled_log {
    category = "kube-controller-manager"
  }
  
  enabled_log {
    category = "kube-scheduler"
  }
  
  enabled_log {
    category = "cluster-autoscaler"
  }
  
  enabled_log {
    category = "guard"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Private DNS Zone for AKS
resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  name                  = "${var.project_name}-${var.environment}-aks-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  
  tags = var.tags
}

# Flux v2 GitOps extension
resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.main.id
  extension_type = "microsoft.flux"
  
  configuration_settings = {
    "helm-controller.enabled"                   = "true"
    "source-controller.enabled"                 = "true"
    "kustomize-controller.enabled"              = "true"
    "notification-controller.enabled"           = "true"
    "image-automation-controller.enabled"       = "true"
    "image-reflector-controller.enabled"        = "true"
  }
}

# Azure Workload Identity for pods
resource "azurerm_user_assigned_identity" "workload" {
  name                = "${var.project_name}-${var.environment}-workload-identity-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

resource "azurerm_federated_identity_credential" "workload" {
  name                = "${var.project_name}-${var.environment}-federated-identity"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.workload.id
  subject             = "system:serviceaccount:default:workload-identity-sa"
}
