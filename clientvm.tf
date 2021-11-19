resource "azurerm_public_ip" "client" {
  name                = "pip-${var.prefix}-client"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "client" {
  name                = "nic-${var.prefix}-client"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.client.id
  }
}

resource "azurerm_network_interface_security_group_association" "client" {
  network_interface_id      = azurerm_network_interface.client.id
  network_security_group_id = azurerm_network_security_group.main.id
}


resource "azurerm_linux_virtual_machine" "client" {
  name                = "vm-${var.prefix}-client"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_E2s_v3"
  network_interface_ids = [
    azurerm_network_interface.client.id
  ]
  admin_username                  = "azureuser"
  admin_password                  = "${var.ospassword}"
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
