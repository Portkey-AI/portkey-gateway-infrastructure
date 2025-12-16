################################################################################
# File: terraform/cluster.tf
################################################################################

module "ecs_cluster" {
  source = "terraform-aws-modules/ecs/aws//modules/cluster"

  count = var.create_cluster ? 1 : 0
  name  = "${var.project_name}-cluster"

  configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = "/aws/ecs/${var.project_name}"
      }
    }
  }

  default_capacity_provider_strategy = {
    primary_provider = {
      weight = 100
      base   = 0
    }
  }

  autoscaling_capacity_providers = {
    primary_provider = {
      auto_scaling_group_arn         = module.autoscaling["primary_provider"].autoscaling_group_arn
      managed_draining               = "ENABLED"
      managed_termination_protection = "ENABLED"

      managed_scaling = {
        maximum_scaling_step_size = 2
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
        target_capacity           = var.target_capacity
      }
    }
  }
}