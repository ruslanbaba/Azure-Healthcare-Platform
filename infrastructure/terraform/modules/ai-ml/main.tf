# AI/ML Integration Module for Advanced Clinical Intelligence
# Azure Healthcare Platform - Machine Learning Services Integration

# Azure Machine Learning Workspace
resource "azurerm_machine_learning_workspace" "healthcare_ml" {
  name                = "${var.project_name}-${var.environment}-ml-workspace-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_insights_id = var.application_insights_id
  key_vault_id       = var.key_vault_id
  storage_account_id = var.storage_account_id
  container_registry_id = var.container_registry_id
  
  # Enterprise security
  public_network_access_enabled = false
  image_build_compute_name      = "cpu-cluster"
  
  # HIPAA compliance
  encryption {
    key_vault_key_id   = var.ml_encryption_key_id
    key_id             = var.ml_encryption_key_id
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    Purpose = "ClinicalIntelligence"
    Component = "MachineLearning"
    Compliance = "HIPAA"
  })
}

# Azure Cognitive Services for Healthcare
resource "azurerm_cognitive_account" "healthcare_text_analytics" {
  name                = "${var.project_name}-${var.environment}-text-analytics-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "TextAnalytics"
  sku_name           = "S"
  
  # HIPAA compliance
  public_network_access_enabled = false
  custom_question_answering_search_service_id = azurerm_search_service.healthcare_search.id
  
  network_acls {
    default_action = "Deny"
    virtual_network_rules {
      subnet_id = var.ml_subnet_id
    }
  }
  
  tags = var.tags
}

# Azure Cognitive Services for Healthcare - FHIR
resource "azurerm_cognitive_account" "healthcare_fhir" {
  name                = "${var.project_name}-${var.environment}-fhir-service-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "HealthcareApis"
  sku_name           = "S1"
  
  # HIPAA compliance
  public_network_access_enabled = false
  
  tags = merge(var.tags, {
    Purpose = "FHIRCompliance"
    Standard = "HL7-FHIR-R4"
  })
}

# Azure Search Service for Clinical Data
resource "azurerm_search_service" "healthcare_search" {
  name                = "${var.project_name}-${var.environment}-search-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "standard"
  replica_count       = 3
  partition_count     = 3
  
  # Security
  public_network_access_enabled = false
  allowed_ips                   = []
  
  # Encryption
  customer_managed_key_enforcement_enabled = true
  
  tags = var.tags
}

# Azure Synapse Analytics for Advanced Analytics
resource "azurerm_synapse_workspace" "healthcare_synapse" {
  name                                 = "${var.project_name}-${var.environment}-synapse-${var.unique_suffix}"
  resource_group_name                  = var.resource_group_name
  location                            = var.location
  storage_data_lake_gen2_filesystem_id = var.data_lake_filesystem_id
  sql_administrator_login              = "synapseadmin"
  sql_administrator_login_password     = var.synapse_admin_password
  
  # HIPAA compliance
  public_network_access_enabled = false
  managed_virtual_network_enabled = true
  
  # Customer-managed encryption
  customer_managed_key {
    key_versionless_id = var.synapse_encryption_key_id
    key_name          = "synapse-cmk"
  }
  
  # Azure AD integration
  aad_admin {
    login     = var.aad_admin_login
    object_id = var.aad_admin_object_id
    tenant_id = var.tenant_id
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    Purpose = "AdvancedAnalytics"
    Component = "DataWarehouse"
  })
}

# Dedicated SQL Pool for Clinical Data Warehouse
resource "azurerm_synapse_sql_pool" "clinical_datawarehouse" {
  name                 = "ClinicalDW"
  synapse_workspace_id = azurerm_synapse_workspace.healthcare_synapse.id
  sku_name            = "DW1000c"
  create_mode         = "Default"
  
  # Backup and recovery
  restore {
    source_database_id = null
    point_in_time     = null
  }
  
  tags = var.tags
}

# Azure Digital Twins for Healthcare IoT
resource "azurerm_digital_twins_instance" "healthcare_twins" {
  name                = "${var.project_name}-${var.environment}-twins-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  # Security
  public_network_access_enabled = false
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    Purpose = "IoTHealthcare"
    Component = "DigitalTwins"
  })
}

# Private Endpoints for ML Services
resource "azurerm_private_endpoint" "ml_workspace" {
  name                = "${azurerm_machine_learning_workspace.healthcare_ml.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.ml_subnet_id

  private_service_connection {
    name                           = "${azurerm_machine_learning_workspace.healthcare_ml.name}-psc"
    private_connection_resource_id = azurerm_machine_learning_workspace.healthcare_ml.id
    subresource_names              = ["amlworkspace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "ml-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.ml_workspace.id]
  }

  tags = var.tags
}

# Private DNS Zone for ML Workspace
resource "azurerm_private_dns_zone" "ml_workspace" {
  name                = "privatelink.api.azureml.ms"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ML Compute Cluster for Training
resource "azurerm_machine_learning_compute_cluster" "healthcare_compute" {
  name                          = "healthcare-cpu-cluster"
  machine_learning_workspace_id = azurerm_machine_learning_workspace.healthcare_ml.id
  location                      = var.location
  vm_priority                   = "Dedicated"
  vm_size                       = "Standard_DS3_v2"
  
  scale_settings {
    min_node_count                       = 0
    max_node_count                       = 10
    scale_down_nodes_after_idle_duration = "PT2M"
  }
  
  # Security
  subnet_resource_id = var.ml_subnet_id
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}
