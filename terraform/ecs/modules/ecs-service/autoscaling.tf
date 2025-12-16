# ============================================================================
# FILE: modules/ecs-service/autoscaling.tf
# ============================================================================

resource "aws_appautoscaling_target" "ecs_service" {
  count = var.ecs_service_config.service_autoscaling_config.enable ? 1 : 0

  max_capacity       = var.ecs_service_config.service_autoscaling_config.max_capacity
  min_capacity       = var.ecs_service_config.service_autoscaling_config.min_capacity
  resource_id        = "service/${local.cluster_name}/${local.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  depends_on         = [aws_ecs_service.service]
}

resource "aws_appautoscaling_policy" "cpu_utilization" {
  count = var.ecs_service_config.service_autoscaling_config.enable && var.ecs_service_config.service_autoscaling_config.target_cpu_utilization != null ? 1 : 0

  name               = "${local.service_name}-cpu-scaling-policy"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value     = var.ecs_service_config.service_autoscaling_config.target_cpu_utilization
    disable_scale_in = var.ecs_service_config.service_autoscaling_config.disable_scale_in
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = var.ecs_service_config.service_autoscaling_config.scale_in_cooldown
    scale_out_cooldown = var.ecs_service_config.service_autoscaling_config.scale_out_cooldown
  }

}

resource "aws_appautoscaling_policy" "memory_utilization" {
  count = var.ecs_service_config.service_autoscaling_config.enable && var.ecs_service_config.service_autoscaling_config.target_memory_utilization != null ? 1 : 0

  name               = "${local.service_name}-memory-scaling-policy"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value     = var.ecs_service_config.service_autoscaling_config.target_memory_utilization
    disable_scale_in = var.ecs_service_config.service_autoscaling_config.disable_scale_in
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    scale_in_cooldown  = var.ecs_service_config.service_autoscaling_config.scale_in_cooldown
    scale_out_cooldown = var.ecs_service_config.service_autoscaling_config.scale_out_cooldown
  }
}
