# High-Performance Data Processing Engine
# Azure Healthcare Platform - Advanced Data Processing

# Azure Event Hubs Dedicated Cluster for High Throughput
resource "azurerm_eventhub_cluster" "healthcare_cluster" {
  name                = "${var.project_name}-${var.environment}-ehcluster-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name           = "Dedicated_1"

  tags = merge(var.tags, {
    Purpose = "HighThroughputIngestion"
    Component = "EventHubsCluster"
  })
}

# Event Hubs Namespace with Dedicated Cluster
resource "azurerm_eventhub_namespace" "healthcare_namespace" {
  name                     = "${var.project_name}-${var.environment}-ehns-${var.unique_suffix}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  sku                      = "Standard"
  capacity                 = 20
  dedicated_cluster_id     = azurerm_eventhub_cluster.healthcare_cluster.id
  auto_inflate_enabled     = true
  maximum_throughput_units = 20

  # HIPAA compliance
  public_network_access_enabled = false
  minimum_tls_version          = "1.2"

  # Customer-managed encryption
  customer_managed_key {
    key_vault_key_id                  = var.eventhub_encryption_key_id
    infrastructure_encryption_enabled = true
  }

  # Network rules
  network_rulesets {
    default_action                 = "Deny"
    public_network_access_enabled  = false
    trusted_service_access_enabled = true

    virtual_network_rule {
      subnet_id                            = var.data_processing_subnet_id
      ignore_missing_virtual_network_service_endpoint = false
    }

    ip_rule {
      ip_mask = "10.0.0.0/8"
      action  = "Allow"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Purpose = "DataIngestion"
    Compliance = "HIPAA"
  })
}

# Event Hub for Patient Records
resource "azurerm_eventhub" "patient_records" {
  name                = "patient-records"
  namespace_name      = azurerm_eventhub_namespace.healthcare_namespace.name
  resource_group_name = var.resource_group_name
  partition_count     = 32
  message_retention   = 7

  # High throughput configuration
  capture_description {
    enabled  = true
    encoding = "AvroDeflate"
    
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = var.archive_container_name
      storage_account_name = var.storage_account_name
    }

    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
  }
}

# Event Hub for Clinical Analytics
resource "azurerm_eventhub" "clinical_analytics" {
  name                = "clinical-analytics"
  namespace_name      = azurerm_eventhub_namespace.healthcare_namespace.name
  resource_group_name = var.resource_group_name
  partition_count     = 16
  message_retention   = 7

  capture_description {
    enabled  = true
    encoding = "AvroDeflate"
    
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = var.analytics_container_name
      storage_account_name = var.storage_account_name
    }

    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
  }
}

# Azure Data Factory v2 for ETL Orchestration
resource "azurerm_data_factory" "healthcare_adf" {
  name                = "${var.project_name}-${var.environment}-adf-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # HIPAA compliance
  public_network_enabled = false

  # Customer-managed encryption
  customer_managed_key_id          = var.adf_encryption_key_id
  customer_managed_key_identity_id = azurerm_user_assigned_identity.adf_identity.id

  # Git configuration for CI/CD
  github_configuration {
    account_name    = var.github_account
    branch_name     = var.github_branch
    git_url         = var.github_url
    repository_name = var.github_repository
    root_folder     = "/data-factory"
  }

  identity {
    type = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.adf_identity.id]
  }

  tags = merge(var.tags, {
    Purpose = "DataOrchestration"
    Component = "DataFactory"
  })
}

# User Assigned Identity for Data Factory
resource "azurerm_user_assigned_identity" "adf_identity" {
  name                = "${var.project_name}-${var.environment}-adf-identity-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Self-Hosted Integration Runtime for Secure Data Movement
resource "azurerm_data_factory_integration_runtime_self_hosted" "healthcare_ir" {
  name            = "healthcare-self-hosted-ir"
  data_factory_id = azurerm_data_factory.healthcare_adf.id
  description     = "Self-hosted integration runtime for HIPAA compliance"
}

# Azure Databricks Workspace for Advanced Analytics
resource "azurerm_databricks_workspace" "healthcare_databricks" {
  name                        = "${var.project_name}-${var.environment}-databricks-${var.unique_suffix}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  sku                         = "premium"
  managed_resource_group_name = "${var.resource_group_name}-databricks-managed"

  # HIPAA compliance
  public_network_access_enabled = false
  network_security_group_rules_required = "NoAzureDatabricksRules"

  # Customer-managed encryption
  customer_managed_key_enabled = true
  
  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = var.vnet_id
    private_subnet_name                                  = var.databricks_private_subnet_name
    public_subnet_name                                   = var.databricks_public_subnet_name
    public_subnet_network_security_group_association_id = var.databricks_public_nsg_id
    private_subnet_network_security_group_association_id = var.databricks_private_nsg_id
    storage_account_name                                 = var.databricks_storage_account_name
    storage_account_sku_name                            = "Standard_LRS"
    vnet_address_prefix                                 = "10.139"
  }

  tags = merge(var.tags, {
    Purpose = "AdvancedAnalytics"
    Component = "Databricks"
    Compliance = "HIPAA"
  })
}

# Azure Stream Analytics for Real-time Processing
resource "azurerm_stream_analytics_job" "healthcare_streaming" {
  name                                     = "${var.project_name}-${var.environment}-stream-${var.unique_suffix}"
  resource_group_name                      = var.resource_group_name
  location                                = var.location
  compatibility_level                      = "1.2"
  data_locale                             = "en-US"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy              = "Adjust"
  output_error_policy                     = "Drop"
  streaming_units                         = 6

  # Customer-managed encryption
  stream_analytics_cluster_id = azurerm_stream_analytics_cluster.healthcare_cluster.id

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Purpose = "RealTimeProcessing"
    Component = "StreamAnalytics"
  })
}

# Stream Analytics Cluster for Dedicated Capacity
resource "azurerm_stream_analytics_cluster" "healthcare_cluster" {
  name                = "${var.project_name}-${var.environment}-sa-cluster-${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  streaming_capacity  = 36

  tags = merge(var.tags, {
    Purpose = "StreamingCluster"
    Component = "StreamAnalytics"
  })
}

# Azure Cosmos DB for Low-Latency NoSQL
resource "azurerm_cosmosdb_account" "healthcare_cosmos" {
  name                      = "${var.project_name}-${var.environment}-cosmos-${var.unique_suffix}"
  location                  = var.location
  resource_group_name       = var.resource_group_name
  offer_type               = "Standard"
  kind                     = "GlobalDocumentDB"
  automatic_failover_enabled = true
  
  # Multi-region setup for high availability
  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = true
  }

  geo_location {
    location          = var.secondary_location
    failover_priority = 1
    zone_redundant    = true
  }

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  # HIPAA compliance
  public_network_access_enabled = false
  is_virtual_network_filter_enabled = true

  virtual_network_rule {
    id                                   = var.cosmos_subnet_id
    ignore_missing_vnet_service_endpoint = false
  }

  # Backup configuration
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Zone"
  }

  # Customer-managed encryption
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Purpose = "NoSQLDatabase"
    Component = "CosmosDB"
    Compliance = "HIPAA"
  })
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "healthcare_db" {
  name                = "healthcare-records"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.healthcare_cosmos.name
  throughput          = 1000
}

# Cosmos DB Container for Patient Records
resource "azurerm_cosmosdb_sql_container" "patient_records" {
  name                  = "patient-records"
  resource_group_name   = var.resource_group_name
  account_name          = azurerm_cosmosdb_account.healthcare_cosmos.name
  database_name         = azurerm_cosmosdb_sql_database.healthcare_db.name
  partition_key_path    = "/patientId"
  partition_key_version = 2
  throughput           = 2000

  # Indexing policy for optimal performance
  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }

    composite_index {
      index {
        path  = "/patientId"
        order = "ascending"
      }
      index {
        path  = "/timestamp"
        order = "descending"
      }
    }
  }

  # Unique key policy
  unique_key {
    paths = ["/patientId", "/recordId"]
  }
}

# Azure Cache for Redis Premium for High Performance Caching
resource "azurerm_redis_cache" "healthcare_cache" {
  name                = "${var.project_name}-${var.environment}-redis-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  capacity            = 6
  family              = "P"
  sku_name           = "Premium"
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  # Redis configuration
  redis_configuration {
    enable_authentication           = true
    maxmemory_reserved             = 50
    maxmemory_delta                = 50
    maxmemory_policy              = "allkeys-lru"
    data_persistence_enabled       = true
    data_persistence_frequency_in_minutes = 60
    data_persistence_max_snapshot_count   = 1
  }

  # HIPAA compliance
  public_network_access_enabled = false
  subnet_id                     = var.redis_subnet_id
  private_static_ip_address     = var.redis_private_ip

  # Zones for high availability
  zones = ["1", "2"]

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Purpose = "HighPerformanceCache"
    Component = "Redis"
  })
}
