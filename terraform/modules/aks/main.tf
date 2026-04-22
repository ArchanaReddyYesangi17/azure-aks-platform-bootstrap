resource "azurerm_user_assigned_identity" "cluster" {
  name                = "id-aks-${var.prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-kubelet-${var.prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
}

resource "azurerm_role_assignment" "network_contributor" {
  scope                = var.aks_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
}

resource "azurerm_kubernetes_cluster" "main" {
  name                      = "aks-${var.prefix}"
  location                  = var.location
  resource_group_name       = var.resource_group_name
  dns_prefix                = "aks-${var.prefix}"
  kubernetes_version        = var.kubernetes_version
  private_cluster_enabled   = true
  sku_tier                  = "Standard"

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_pool.vm_size
    node_count                   = var.system_node_pool.node_count
    min_count                    = var.system_node_pool.min_count
    max_count                    = var.system_node_pool.max_count
    enable_auto_scaling          = true
    vnet_subnet_id               = var.aks_subnet_id
    pod_subnet_id                = var.pod_subnet_id
    only_critical_addons_enabled = true
    os_disk_type                 = "Ephemeral"

    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.prefix
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  azure_active_directory_role_based_access_control {
    managed                = true
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "userDefinedRouting"
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  auto_scaler_profile {
    balance-similar-node-groups  = true
    scale-down-delay-after-add   = "10m"
    scale-down-unneeded-time     = "10m"
  }

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "workload" {
  name                  = "workload"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.workload_node_pool.vm_size
  min_count             = var.workload_node_pool.min_count
  max_count             = var.workload_node_pool.max_count
  enable_auto_scaling   = true
  vnet_subnet_id        = var.aks_subnet_id
  pod_subnet_id         = var.pod_subnet_id
  os_disk_type          = "Ephemeral"

  node_labels = {
    "nodepool-type" = "workload"
  }

  tags = var.tags
}
