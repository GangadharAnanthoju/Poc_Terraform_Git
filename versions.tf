terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.3"
    }
  }
  backend "azurerm" {
    resource_group_name  = "rg-sysint-terraform-state-dev-eastus"
    storage_account_name = "st01terraformstate"
    container_name       = "tfstate"
    key                  = "terraform.tfstate-dev"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "d835f9fb-e4f6-4ffe-9740-e32ebdef91ff"
}
