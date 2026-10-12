# Architecture

This module implements the Cloud Adoption Framework's [Azure architecture for a unified data platform](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/data/architecture-azure-landing-zones-unify-data-platform). Refer to that article for the full rationale behind the landing-zone model. This document describes how this repository maps onto it.

## Landing-Zone Model

![Unified Data Platform Landing Zones for Fabric and Azure Databricks architecture diagram](images/unified-data-platform-architecture.png)

Green boxes are the Fabric side of this repository, red boxes are the Azure Databricks side, gold is the shared OneLake analytical layer, and white or grey boxes are existing ALZ platform components consumed as inputs (resource group IDs, subnet IDs, private DNS zone IDs), not recreated.

**Data management landing zone (DMLZ)**: an Azure subscription boundary hosting one or more Fabric capacities. Capacity creation is an ARM concern, delegated to the published [`avm-res-fabric-capacity`](https://github.com/Azure/terraform-azure-avm-res-fabric-capacity) module (`modules/data-management-landing-zone`). A DMLZ can be centralized (one shared capacity across domains) or decentralized (one capacity per domain); the module accepts one or more DMLZ entries per apply.

**Fabric data landing zone (Fabric DLZ)**: a logical Fabric boundary containing a business domain, workspaces, delegated administration, identity, and network policy (`modules/fabric-data-landing-zone`). The module accepts one or more Fabric DLZ entries per apply. Workspace network restrictions default off per workspace. Once enabled, outbound, cloud connection, gateway, and Git policies fail closed, with inbound denial as a separate operator acknowledged phase after private link verification.

**Azure Databricks data landing zone (Databricks DLZ)**: a sibling, independent Azure subscription and network boundary (`modules/databricks-data-landing-zone`) provisioning the VNet injected Databricks workspace and its Access Connector managed identity, consuming existing OneLake item identifiers rather than creating a second analytical data lake. The module accepts zero or more Databricks DLZ entries per apply.

**Application landing zones** consume Fabric workspaces only through explicitly approved mechanisms: mirroring, OneLake shortcuts, APIs, or managed private endpoints. They are peer boundaries to the DMLZ and Fabric DLZ, not parents or children of them. There is no direct relationship between a Fabric capacity and an application landing zone, only between a workspace and the application landing zones approved to consume it.

**Fabric tenant governance** (tenant wide Fabric settings) is out of scope for this module. It is a tenant scoped, singleton concern with no capacity, resource group, or subscription boundary, so it does not fit the repeatable, per domain DMLZ and Fabric DLZ composition this module provides. Configure it once per Fabric tenant, outside this module, before deploying any DMLZ or Fabric DLZ. See [Prerequisites](../README.md#prerequisites) for the required settings.

The unified root requires at least one Fabric capacity and one Fabric data landing zone. OneLake remains the central analytical layer even though Databricks retains its own subscription and lifecycle boundary. Consumers needing Databricks without Fabric should use a dedicated Databricks module instead of weakening this composition contract.

## Scope Boundary

This module establishes where a data product can run and which controls surround it, not what runs there. Medallion workspaces, lakehouses, warehouses, pipelines, semantic models, and data access roles belong to a separate, future data product architecture module, keeping platform policy stable while workload patterns evolve.

## OneLake Guidance Applied

- Default to virtualized access through shortcuts or selective mirroring instead of unnecessary replication.
- Organize ownership around domains and workspaces.
- Keep Bronze, Silver, and Gold medallion concerns for the workload module.
- Use a single governed OneLake namespace and open formats where feasible.

OneLake catalog federation is the preferred no-copy path for governed, read-only Unity Catalog queries. The Access Connector's managed identity supports this without the module creating federation connections or foreign catalogs itself. Direct OneLake ABFS access remains available for supported read and write workloads via caller-selected global, regional, or workspace-private endpoints. This pattern does not claim OneLake as a Unity Catalog metastore root.

## Capacity Model

- Centralized: shared capacities for immature or variable domains.
- Decentralized: dedicated capacities for mature domains with stable demand or explicit chargeback.
- Hybrid: shared by default, with graduation criteria for dedicated capacity.

Region and SKU are governance decisions validated against residency, private networking, capacity limits, and DR requirements. Fabric capacity administration uses Entra user UPNs or service-principal object IDs, since the ARM API does not accept Entra groups. `capacity_role_assignments` covers Azure RBAC separately. Entra groups remain the mechanism for Fabric domain and workspace roles.

## Provider and AVM Status

Each scope declares only providers it uses directly (TFNFR26), with minimum and maximum major version constraints: `azapi >= 2.12, < 3.0`, `fabric >= 1.14, < 2.0`, `modtm ~> 0.3`, `random ~> 3.5`, and `time ~> 0.9`. AzureRM is neither declared nor configured in any scope. Modtm remains required by the latest released AVM generator; this is an unresolved SFR3 tooling rollout gap, not a claim of current telemetry compliance. Provider lock files are not committed, per the AVM contribution flow.

DMLZ composes the published resource-group AVM and [`avm-res-fabric-capacity`](https://github.com/Azure/terraform-azure-avm-res-fabric-capacity) v0.1.0. The Databricks landing zone retains the published resource-group and [`avm-res-databricks-accessconnector`](https://registry.terraform.io/modules/Azure/avm-res-databricks-accessconnector/azurerm/0.1.0) v0.1.0 dependencies, but owns its workspace, encryption, diagnostics, and locks through AzAPI. The Fabric landing zone owns the workspace private-link service, private endpoint, and private DNS zone group through AzAPI. These resources preserve full parent IDs, avoiding name-only subscription targeting. The pattern exposes configurable resource types, retries, timeouts, and ignored body paths for its owned AzAPI resources.
