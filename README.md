# Portkey Gateway Infrastructure

Infrastructure-as-Code for deploying **Portkey Hybrid Gateway** across multiple cloud platforms.

## Overview

This repository contains Terraform configurations for deploying the Portkey AI Gateway in hybrid deployment mode across multiple cloud platforms.


## Supported Platforms

| Platform | Status | Documentation |
|----------|--------|---------------|
| **Amazon ECS** | ✅ Available | [ECS Deployment Guide](terraform/ecs/README.md) |
| **Azure Container Apps (ACA)** |  ✅ Available | [ACA Deployment Guide](terraform/aca/README.md) |

## Repository Structure

```
portkey-gateway-infrastructure/
├── README.md                         # This file
├── architecture/                     # Architecture diagrams
├── cloudformation/                   # AWS CloudFormation templates
│   └── secrets.yaml                  # Secrets management template
└── terraform/
    └── ecs/                          # Amazon ECS deployment
        ├── README.md                 # Complete ECS guide
        ├── VARIABLES.md              # Configuration reference
        ├── environments/             # Environment configs (dev/prod)
        ├── modules/                  # Reusable Terraform modules
        └── *.tf                      # Terraform configuration
```

## Getting Help

- **Documentation**: [docs.portkey.ai](https://docs.portkey.ai)
- **Issues**: Open an issue in this repository
- **Support**: Contact Portkey support team
