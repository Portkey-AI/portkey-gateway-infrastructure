################################################################################
# File: terraform/aca/providers.tf
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.90.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

################################################################################
# Provider Configuration (for clone & deploy)
# Note: When used as a module, the parent's provider config takes precedence
################################################################################

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # subscription_id is optional - provider will auto-detect from Azure CLI/environment if not set
  subscription_id = var.subscription_id
}
