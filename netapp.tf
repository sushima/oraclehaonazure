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
