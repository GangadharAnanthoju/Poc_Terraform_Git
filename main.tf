resource "random_string" "suffix1" {
  length  = 10
  upper   = false
  special = false
}

resource "azurerm_resource_group" "main" {
  name     = "rg-delete-${var.application_name}-${var.environment_name}"
  location = var.primary_location
}
