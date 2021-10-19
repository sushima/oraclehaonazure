# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
  required_version = ">= 0.14.9"
}

provider "http" {
}

data "http" "clientip" {
  url = "https://ipv4.icanhazip.com/"
}

provider "azurerm" {
  features {}
}

provider "azuread" {
}

data "azurerm_subscription" "primary" {
}

data "azurerm_client_config" "main" {
}

resource "azurerm_resource_group" "main" {
  name     = "000-rg-${var.prefix}"
  location = "japaneast"
}


resource "azurerm_network_security_group" "main" {
  name                = "nsg-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_network_security_rule" "main" {
  name                        = "AllowSSHInBound"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = 1001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = 22
  source_address_prefix       = "${chomp(data.http.clientip.body)}/32"
  destination_address_prefix  = "*"
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.prefix}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "netapp" {
  name                 = "snet-netapp"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]


  delegation {
    name = "netapp"

    service_delegation {
      name    = "Microsoft.Netapp/volumes"
      actions = ["Microsoft.Network/networkinterfaces/*", "Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

variable "count_vm" {
  default = "2"
}

resource "azurerm_public_ip" "main" {
  name                = "pip-${var.prefix}-${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
  count               = var.count_vm
}

resource "azurerm_network_interface" "main" {
  name                = "nic-${var.prefix}${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  count               = var.count_vm

  ip_configuration {
    name                          = "internal${count.index}"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main[count.index].id
  network_security_group_id = azurerm_network_security_group.main.id
  count                     = var.count_vm
}


resource "azurerm_linux_virtual_machine" "main" {
  name                = "vm-${var.prefix}${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_E2s_v3"
  network_interface_ids = [
    azurerm_network_interface.main[count.index].id
  ]
  count                           = var.count_vm
  admin_username                  = "azureuser"
  admin_password                  = "Himitsu999!"
  disable_password_authentication = false

  source_image_reference {
    publisher = "oracle"
    offer     = "oracle-database-19-3"
    sku       = "oracle-database-19-0904"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
}

resource "azurerm_netapp_account" "main" {
  name                = "netapp-${var.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}


resource "azurerm_netapp_pool" "main" {
  name                = "pool"
  account_name        = azurerm_netapp_account.main.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_level       = "Standard"
  size_in_tb          = 4
}

resource "azurerm_netapp_volume" "main" {
  lifecycle {
    prevent_destroy = true
  }

  name                       = "vol"
  account_name               = azurerm_netapp_account.main.name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  pool_name                  = azurerm_netapp_pool.main.name
  volume_path                = "oradata"
  service_level              = "Standard"
  subnet_id                  = azurerm_subnet.netapp.id
  protocols                  = ["NFSv3"]
  security_style             = "Unix"
  storage_quota_in_gb        = 4096
  snapshot_directory_visible = false

  export_policy_rule {
    rule_index          = 1
    allowed_clients     = azurerm_subnet.vm.address_prefixes
    protocols_enabled   = ["NFSv3"]
    root_access_enabled = true
    unix_read_write     = true
  }
}

resource "azurerm_virtual_machine_extension" "main" {
  name                 = "customscript${count.index}"
  virtual_machine_id   = azurerm_linux_virtual_machine.main[count.index].id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"
  count                = var.count_vm

  settings = <<-SETTINGS
        {"script": "${base64encode(templatefile("./ossetup.sh", {
  vmname0   = azurerm_linux_virtual_machine.main[0].name
  vmname1   = azurerm_linux_virtual_machine.main[1].name
  netappvol = azurerm_netapp_volume.main.volume_path
  netappip  = azurerm_netapp_volume.main.mount_ip_addresses.0
  node      = count.index
  myip      = azurerm_linux_virtual_machine.main[count.index].private_ip_address
}))}"}
    SETTINGS
}
