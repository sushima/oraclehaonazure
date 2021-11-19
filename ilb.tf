resource "azurerm_lb" "main" {
  name                = "lb-${var.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name              = "lb-privateip-${var.prefix}"
    subnet_id         = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_rule" "main" {
  resource_group_name            = azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "LBRuleOrcl"
  protocol                       = "Tcp"
  frontend_port                  = 1521
  backend_port                   = 1521
  frontend_ip_configuration_name = "lb-privateip-${var.prefix}"
  probe_id                       = azurerm_lb_probe.main.id
  backend_address_pool_id        = azurerm_lb_backend_address_pool.main.id
}

resource "azurerm_lb_backend_address_pool" "main" {
 loadbalancer_id     = azurerm_lb.main.id
 name                = "lb-backend-${var.prefix}"
}

resource "azurerm_lb_probe" "main" {
 resource_group_name = azurerm_resource_group.main.name
 loadbalancer_id     = azurerm_lb.main.id
 name                = "orcl-running-probe"
 port                = 1521
}

resource "azurerm_lb_backend_address_pool_address" "main" {
  name                    = "backaddr${count.index}"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
  virtual_network_id      = azurerm_virtual_network.main.id
  ip_address              = azurerm_linux_virtual_machine.main[count.index].private_ip_address
  count                   = var.count_vm
}
