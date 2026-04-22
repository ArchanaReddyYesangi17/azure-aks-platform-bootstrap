variable "prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "kubernetes_version" { type = string }
variable "aks_subnet_id" { type = string }
variable "pod_subnet_id" { type = string }
variable "log_analytics_workspace" { type = string }
variable "key_vault_id" { type = string }
variable "acr_id" { type = string }
variable "admin_group_object_ids" { type = list(string) }
variable "tags" { type = map(string) }

variable "system_node_pool" {
  type = object({
    vm_size    = string
    node_count = number
    min_count  = number
    max_count  = number
  })
}

variable "workload_node_pool" {
  type = object({
    vm_size   = string
    min_count = number
    max_count = number
  })
}
