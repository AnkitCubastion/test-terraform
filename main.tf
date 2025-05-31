terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.31.0"
    }
  }
}

provider "azurerm" {
    features {}
    subscription_id = var.subscription_id
    client_id       = var.client_id
    client_secret   = var.client_secret
    tenant_id       = var.tenant_id  
}

resource "azurerm_resource_group" "arg" {
  name     = "lne"
  location = "East US"
}

resource "azurerm_virtual_network" "avn" {
  name                = "avn"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name
  address_space       = ["10.224.0.0/12"]
}

resource "azurerm_subnet" "as-akc" {
  name                 = "as-akc"
  resource_group_name  = azurerm_resource_group.arg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.224.0.0/16"]
}

resource "azurerm_subnet" "as-aag" {
  name                 = "as-aag"
  resource_group_name  = azurerm_resource_group.arg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.225.0.0/16"]
}

resource "azurerm_subnet" "as-avm" {
  name                 = "as-avm"
  resource_group_name  = azurerm_resource_group.arg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.226.0.0/16"]
}

resource "azurerm_public_ip" "api" {
  name                = "avm-pi"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "api-ag" {
  name                = "aag-pi"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "ani" {
  name                = "ani"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name

  ip_configuration {
    name                          = "ani-ic"
    subnet_id                     = azurerm_subnet.as-avm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.api.id
  }
}

resource "azurerm_network_security_group" "ansg" {
  name                = "ansg"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "asnsga" {
  subnet_id                 = azurerm_subnet.as-avm.id
  network_security_group_id = azurerm_network_security_group.ansg.id
}

##### akc #####

resource "azurerm_kubernetes_cluster" "akc" {
  name                = "akc"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name
  dns_prefix          = "akc-dns"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "standard_d2as_v5"
    vnet_subnet_id = azurerm_subnet.as-akc.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
  }

  private_cluster_enabled = true
}

##### alvm #####

resource "azurerm_linux_virtual_machine" "alvm" {
  name                = "alvm"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  size                = "standard_d2as_v5"
  admin_username      = "ankit090701"
  admin_password = "Drowssap@3302"
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.ani.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

##### aag #####

resource "azurerm_application_gateway" "aag" {
  name                = "aag"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "aag-gip"
    subnet_id = azurerm_subnet.as-aag.id
  }

  frontend_port {
    name = "fp"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "fic"
    public_ip_address_id = azurerm_public_ip.api-ag.id
  }

  backend_address_pool {
    name = "bap"
  }

  backend_http_settings {
    name                  = "bhs"
    cookie_based_affinity = "Disabled"
    path                  = "/path1/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "hl"
    frontend_ip_configuration_name = "fic"
    frontend_port_name             = "fp"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rrr"
    priority                   = 101
    rule_type                  = "Basic"
    http_listener_name         = "hl"
    backend_address_pool_name  = "bap"
    backend_http_settings_name = "bhs"
  }
}