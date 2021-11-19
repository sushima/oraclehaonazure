variable "count_vm" {
  default = "2"
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
  ospassword = "${var.ospassword}"
}))}"}
    SETTINGS
}