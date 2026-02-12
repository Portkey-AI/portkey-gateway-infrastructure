################################################################################
# File: terraform/aca/redis.tf
################################################################################

#########################################################################
#                     REDIS CONTAINER APP                                #
#########################################################################

module "redis" {
  source = "./modules/container-app"
  count  = var.redis_config.redis_type == "redis" ? 1 : 0

  name                         = "redis"
  resource_group_name          = local.resource_group_name
  location                     = var.azure_region
  container_app_environment_id = azurerm_container_app_environment.main.id
  user_assigned_identity_id    = azurerm_user_assigned_identity.aca.id
  tags                         = local.tags

  # Container configuration
  container_config = {
    image                 = var.redis_image.image
    tag                   = var.redis_image.tag
    cpu                   = var.redis_config.cpu
    memory                = var.redis_config.memory
    min_replicas          = 1
    max_replicas          = 1
    environment_variables = {}
    secrets               = {}
  }

  # No registry credentials needed - public image
  registry_type       = "dockerhub"
  docker_registry_url = "docker.io"
  docker_credentials  = null

  # Ingress configuration - internal TCP only
  ingress_enabled     = true
  ingress_external    = false
  ingress_target_port = 6379
  ingress_transport   = "tcp"

  # Health probes (TCP on port 6379 - checks Redis is accepting connections)
  health_probes = {
    liveness = {
      initial_delay           = 10
      interval_seconds        = 15
      timeout                 = 3
      failure_count_threshold = 3
    }
    readiness = {
      initial_delay           = 5
      interval_seconds        = 10
      timeout                 = 3
      failure_count_threshold = 3
    }
    startup = {
      interval_seconds        = 5
      timeout                 = 3
      failure_count_threshold = 5
    }
  }

  depends_on = [
    azurerm_container_app_environment.main
  ]
}
