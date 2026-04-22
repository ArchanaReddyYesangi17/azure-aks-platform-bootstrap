locals {
  prefix = "platform-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
  })
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_key_vault" "main" {
  name                       = "kv-${local.prefix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    virtual_network_subnet_ids = [
      module.networking.aks_subnet_id,
      module.networking.private_endpoint_subnet_id,
    ]
  }

  tags = local.common_tags
}

resource "azurerm_container_registry" "main" {
  name                = replace("acr${local.prefix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Premium"
  admin_enabled       = false

  network_rule_set {
    default_action = "Deny"
    virtual_network {
      action    = "Allow"
      subnet_id = module.networking.aks_subnet_id
    }
  }

  tags = local.common_tags
}

module "networking" {
  source = "./modules/networking"

  prefix                       = local.prefix
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  vnet_address_space           = var.vnet_address_space
  aks_subnet_cidr              = var.aks_subnet_cidr
  pod_subnet_cidr              = var.pod_subnet_cidr
  private_endpoint_subnet_cidr = var.private_endpoint_subnet_cidr
  tags                         = local.common_tags
}

module "aks" {
  source = "./modules/aks"

  prefix                  = local.prefix
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  kubernetes_version      = var.kubernetes_version
  system_node_pool        = var.system_node_pool
  workload_node_pool      = var.workload_node_pool
  aks_subnet_id           = module.networking.aks_subnet_id
  pod_subnet_id           = module.networking.pod_subnet_id
  log_analytics_workspace = azurerm_log_analytics_workspace.main.id
  key_vault_id            = azurerm_key_vault.main.id
  acr_id                  = azurerm_container_registry.main.id
  admin_group_object_ids  = var.admin_group_object_ids
  tags                    = local.common_tags
}

data "azurerm_client_config" "current" {}
