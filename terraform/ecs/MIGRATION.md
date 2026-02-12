# Migration Guide - ECS Module v1.0.0 to v1.1.0

## Overview

Version 1.1.0 introduces enhanced deployment strategies (Blue/Green, Canary, Linear) with backward compatibility maintained for existing configurations.

## Breaking Changes

**None** - Full backward compatibility is maintained.

## What's New

- **Advanced Deployment Strategies**: Support for Canary and Linear deployment strategies in addition to Blue/Green
- **Flexible Circuit Breaker**: Circuit breaker configuration is now controllable for all deployment types
- **Improved Module Structure**: Enhanced internal organization while maintaining backward compatibility

## For End Users (Clone & Deploy)

**No action required** - All existing tfvars files will continue to work without modification.

Your existing configuration:
```hcl
gateway_deployment_configuration = {
  enable_blue_green    = false
  canary_configuration = null
  linear_configuration = null
}

gateway_deployment_circuit_breaker = {
  enable   = true
  rollback = true
}
```

Will continue to work in v1.1.0 without any changes.

## For Module Users (Advanced)

If you were using `modules/ecs-service` directly (rare), the new structure is backward compatible.

### Old Structure (Still Supported)

```hcl
module "my_service" {
  source = "./modules/ecs-service"
  
  ecs_service_config = {
    # Old way - still works
    enable_blue_green = true
    # ... other config
  }
}
```

### New Structure (Recommended)

```hcl
module "my_service" {
  source = "./modules/ecs-service"
  
  ecs_service_config = {
    # New way - more flexible
    deployment_configuration = {
      enable_blue_green = true
      # Optional: add canary or linear configs
    }
    deployment_circuit_breaker = {
      enable   = true
      rollback = true
    }
    # ... other config
  }
}
```

### Important Notes

1. **Don't mix old and new**: You cannot use both `enable_blue_green` (old) and `deployment_configuration` (new) in the same configuration
2. **Deprecation**: The old `enable_blue_green` field is deprecated and will be removed in v2.0.0
3. **Recommendation**: New deployments should use the `deployment_configuration` structure

## New Features in v1.1.0

### Canary Deployment

```hcl
gateway_deployment_configuration = {
  enable_blue_green = false
  canary_configuration = {
    canary_percent              = 20  # Route 20% traffic to new version
    canary_bake_time_in_minutes = 5   # Wait 5 minutes before full rollout
  }
  linear_configuration = null
}
```

### Linear Deployment

```hcl
gateway_deployment_configuration = {
  enable_blue_green = false
  canary_configuration = null
  linear_configuration = {
    step_percent              = 10  # Increase traffic by 10% each step
    step_bake_time_in_minutes = 3   # Wait 3 minutes between steps
  }
}
```

## Rollback Plan

If you encounter any issues after upgrading to v1.1.0, you can safely rollback to v1.0.0 without any configuration changes required.

## Support

For questions or issues:
- Open an issue in the GitHub repository
- Contact Portkey support team
