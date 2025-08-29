# Networking Module for Azure Healthcare Analytics Platform

resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-${var.environment}-vnet-${var.unique_suffix}"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-vnet"
    Type = "Network"
  })
}

# Network Security Group for AKS
resource "azurerm_network_security_group" "aks" {
  name                = "${var.project_name}-${var.environment}-aks-nsg-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Allow internal cluster communication
  security_rule {
    name                       = "AllowInternalCluster"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "10.0.1.0/24"
  }

  # Allow HTTPS from API Management
  security_rule {
    name                       = "AllowHTTPSFromAPIM"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.0.4.0/24"
    destination_address_prefix = "10.0.1.0/24"
  }

  # Deny all other inbound traffic
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# AKS Subnet
resource "azurerm_subnet" "aks" {
  name                 = "${var.project_name}-${var.environment}-aks-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
  
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.Sql",
    "Microsoft.ContainerRegistry"
  ]
}

# Data Subnet
resource "azurerm_subnet" "data" {
  name                 = "${var.project_name}-${var.environment}-data-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
  
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault"
  ]
}

# Functions Subnet
resource "azurerm_subnet" "functions" {
  name                 = "${var.project_name}-${var.environment}-functions-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]
  
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.Web"
  ]
  
  delegation {
    name = "Microsoft.Web.serverFarms"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# API Management Subnet
resource "azurerm_subnet" "apim" {
  name                 = "${var.project_name}-${var.environment}-apim-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.4.0/24"]
  
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault"
  ]
}

# Application Gateway Subnet
resource "azurerm_subnet" "gateway" {
  name                 = "${var.project_name}-${var.environment}-gateway-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.5.0/24"]
}

# Private Endpoints Subnet
resource "azurerm_subnet" "private_endpoints" {
  name                 = "${var.project_name}-${var.environment}-pe-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.6.0/24"]
  
  private_endpoint_network_policies_enabled = false
}

# Associate NSG with AKS subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Route Table for controlled routing
resource "azurerm_route_table" "main" {
  name                = "${var.project_name}-${var.environment}-rt-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  route {
    name           = "default"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
  
  tags = var.tags
}

# Associate route table with subnets
resource "azurerm_subnet_route_table_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  route_table_id = azurerm_route_table.main.id
}

resource "azurerm_subnet_route_table_association" "functions" {
  subnet_id      = azurerm_subnet.functions.id
  route_table_id = azurerm_route_table.main.id
}

# DDoS Protection Plan
resource "azurerm_network_ddos_protection_plan" "main" {
  name                = "${var.project_name}-${var.environment}-ddos-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  tags = var.tags
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "gateway" {
  name                = "${var.project_name}-${var.environment}-gateway-pip-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                = "Standard"
  
  tags = var.tags
}

# NAT Gateway for outbound connectivity
resource "azurerm_public_ip" "nat_gateway" {
  name                = "${var.project_name}-${var.environment}-nat-pip-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                = "Standard"
  
  tags = var.tags
}

resource "azurerm_nat_gateway" "main" {
  name                = "${var.project_name}-${var.environment}-nat-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name           = "Standard"
  
  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat_gateway.id
}

resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "functions" {
  subnet_id      = azurerm_subnet.functions.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
