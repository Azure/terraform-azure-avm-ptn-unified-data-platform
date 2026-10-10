# Source Register

The sources directly affected by the review fixes below were rechecked on 2026-09-30. Older rows retain their original observation dates rather than implying that unrelated product guidance was refreshed.

| Source | Version/date observed | Design use |
| --- | --- | --- |
| CAF Fabric Architecture for a Unified Data Platform | 2026-03-10 | Capacity, region, workspace, domain, and DR decisions |
| CAF Azure Architecture for a Unified Data Platform | 2026-03-10 | DMLZ, application LZ integration, optional Azure DLZ model |
| Azure Verified Modules Terraform pattern index and ALZ repositories | Catalog reviewed 2026-07-23 | Pattern composition and ALZ compatibility |
| Microsoft Fabric Terraform provider | v1.14.0, reviewed 2026-09-30 | Implemented Fabric resources and preview workspace CMK |
| Fabric tenant setting Terraform resource and REST API | v1.14.0, generally available since provider v1.8.0, reviewed 2026-10-01 | Declarative tenant settings, security-group scope, delegation, typed properties, deletion behavior, and permissions; kept out of module scope as a tenant-wide prerequisite |
| Fabric capacity ARM schema | `Microsoft.Fabric/capacities@2023-11-01`, reviewed 2026-07-23 | Stable AzAPI capacity contract and administrator identity semantics |
| Databricks Access Connector ARM schema | `Microsoft.Databricks/accessConnectors@2024-05-01`, reviewed 2026-07-23 | Stable AzAPI Access Connector contract and system-assigned identity output |
| AVM resource group, Access Connector, capacity, and utility interfaces | v0.4.0 / v0.1.0 / v0.1.0 / v0.7.0, reviewed 2026-09-30 | Retained published AzAPI-based dependencies; workspace and private endpoints are owned directly to remove AzureRM requirements |
| Microsoft.Network private endpoint and DNS zone group schemas | 2024-05-01, reviewed 2026-09-30 | Full parent-ID targeting, connection settings, shared DNS-zone binding, and replacement semantics |
| Azure Monitor diagnostic settings REST API | 2021-05-01-preview, reviewed 2026-09-30 | Unique setting names and Dedicated/null destination type translation |
| AVM SFR3 and SFR4 / Avm.Authoring | SFR3 updated 2026-09-29; released authoring0.19.0, reviewed 2026-09-30 | Reporting location wiring and documented unreleased telemetry generator rollout (tools PR192) |
| Workspace outbound access protection | Updated 2026-07-15 | Optional workspace protection; deny-by-default outbound/cloud/gateway behavior when enabled; Git policy is independently configurable |
| Workspace-level private links | Updated 2026-05-27 | Inbound private-link design and DNS/resource sequence |
| Fabric security overview | Updated 2026-07-14 | Identity, network, encryption, and data-security controls |
| Fabric governance and compliance overview | Updated 2026-05-11 | Fabric-native domains, catalog, tags, lineage, endorsement, monitoring |
| OneLake disaster recovery and data protection | Updated 2026-07-07 | Capacity DR, ZRS/LRS, seven-day soft delete |
| Reliability in Microsoft Fabric | Updated 2026-05-19 | Availability zones, failover behavior, DR responsibility |
| Customer-managed keys for Fabric workspaces | Updated 2026-09-08, reviewed 2026-09-30 | Fabric Platform CMK service principal, tenant setting, key permissions, versionless keys, and disablement behavior |
| OneLake Architectural Guidance whitepaper (local, 12 pages) | Supplied by project owner | Virtualize by default, domain/data mesh, medallion, platform simplification |
| Azure MCP Server | Docs updated 2026-07-17; Azure MCP 2.0 GA | AVM, Terraform, WAF, and Azure validation tooling |
| Microsoft Fabric MCP Server | Public Preview observed 2026-07-23 | Current Fabric API/schema and OneLake development context |
| Azure Databricks WAF and VNet injection | Updated 2026-07-20 | Dedicated subnets, SCC/no public IP, explicit outbound connectivity, network ownership |
| Azure Databricks Private Link concepts | Updated 2026-07-22 | Front-end, browser-authentication, classic back-end, and serverless isolation boundaries |
| Integrate OneLake with Azure Databricks | Updated 2026-06-23 | Direct ABFS read/write, service-principal authentication, serverless limitations, single-writer guidance |
| OneLake catalog federation | Updated 2026-06-17 | Managed-identity federation, Fabric prerequisites, read-only foreign catalogs |
| Unity Catalog managed identities and external locations | Updated 2026-07-02 / 2026-06-11 | Access Connector pattern and ADLS Gen2 managed-storage boundary |
| AzureRM provider implementation | v4.81.0, migration reference only | Legacy state and lifecycle semantics; not a runtime dependency of this pattern |

## Primary Links

- https://learn.microsoft.com/azure/cloud-adoption-framework/data/architecture-fabric-data-lake-unify-data-platform
- https://learn.microsoft.com/azure/cloud-adoption-framework/data/architecture-azure-landing-zones-unify-data-platform
- https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-pattern-modules/
- https://registry.terraform.io/providers/microsoft/fabric/latest/docs
- https://registry.terraform.io/providers/microsoft/fabric/1.12.0/docs/resources/tenant_setting
- https://learn.microsoft.com/rest/api/fabric/admin/tenants/update-tenant-setting
- https://learn.microsoft.com/azure/templates/microsoft.fabric/2023-11-01/capacities
- https://learn.microsoft.com/azure/templates/microsoft.databricks/2024-05-01/accessconnectors
- https://learn.microsoft.com/fabric/security/security-workspace-level-private-links-overview
- https://learn.microsoft.com/fabric/security/workspace-outbound-access-protection-overview
- https://registry.terraform.io/providers/microsoft/fabric/1.12.0/docs/resources/workspace_git_outbound_policy
- https://registry.terraform.io/providers/microsoft/fabric/1.12.0/docs/resources/workspace_network_communication_policy
- https://registry.terraform.io/providers/microsoft/fabric/1.12.0/docs/resources/workspace_outbound_cloud_connection_rules
- https://learn.microsoft.com/fabric/governance/governance-compliance-overview
- https://learn.microsoft.com/azure/reliability/reliability-fabric
- https://github.com/microsoft/mcp
- https://learn.microsoft.com/azure/databricks/security/network/classic/vnet-inject
- https://learn.microsoft.com/azure/databricks/security/network/classic/private-link
- https://learn.microsoft.com/fabric/onelake/onelake-azure-databricks
- https://learn.microsoft.com/azure/databricks/query-federation/onelake
- https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/azure-managed-identities
- https://learn.microsoft.com/fabric/security/workspace-customer-managed-keys
- https://learn.microsoft.com/azure/templates/microsoft.network/2024-05-01/privateendpoints
- https://learn.microsoft.com/azure/templates/microsoft.network/2024-05-01/privateendpoints/privatednszonegroups
- https://learn.microsoft.com/rest/api/monitor/diagnostic-settings/create-or-update?view=rest-monitor-2021-05-01-preview
- https://azure.github.io/Azure-Verified-Modules/spec/SFR3/
- https://azure.github.io/Azure-Verified-Modules/spec/SFR4/
- https://github.com/Azure/azure-verified-modules-tools/pull/192