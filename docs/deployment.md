# Deployment Guide

## 1. Establish ALZ Prerequisites

Use existing ALZ pattern modules for management groups, policy, subscription vending, connectivity, DNS, monitoring, and application landing zones. Prepare DMLZ subscriptions and, for private workspaces, a connectivity-managed private-endpoint subnet and `privatelink.fabric.microsoft.com` private DNS zone.

Do not use a local Terraform backend for production.

## 2. Confirm Fabric Tenant Prerequisites

Confirm the required Fabric tenant settings are already enabled by whoever owns Fabric tenant governance. See [Prerequisites](../README.md#prerequisites) for the required settings. This module does not configure tenant settings.

For OneLake federation, confirm the narrowly scoped Fabric settings for service principals or managed identities, apps outside Fabric, and short-lived user-delegated SAS tokens are enabled at the tenant. Enable OneLake delegated SAS authentication on each target Fabric workspace and approve the Databricks Access Connector identity for the required workspace role.

## 3. Configure Authentication

For local design validation, Azure CLI user authentication can be used. For CI/CD, configure workload identity federation and pass authentication through provider environment variables. Do not declare credentials as Terraform variables.

The Fabric provider needs a Fabric administrator or appropriately delegated permissions for domains, plus workspace administration for workspace controls. Azure providers need scoped rights to the DMLZ and private-link resource groups/subnets/DNS.

Supply capacity administration members as Entra user UPNs or service-principal object IDs. Do not supply Entra group object IDs to the capacity ARM administration list. Model Azure RBAC independently with `capacity_role_assignments`.

The Databricks landing-zone deployment identity needs rights to its Azure data landing-zone resource group and join/delegation rights for both dedicated workspace subnets. It does not need a OneLake client secret.

Databricks workspace/account governance uses a separate state and the `databricks/databricks` provider configured by that state's caller. Pass only the landing-zone outputs it needs; do not pass Databricks credentials through this ARM pattern.

## 4. Supply Inputs

The examples deploy without input for testing: they create stand-ins for their network, private DNS, monitoring, and OneLake prerequisites. A production deployment calls the module directly and supplies the real ALZ values instead. Use `examples/secure-baseline` as the starting shape and replace its example-owned resources with the ALZ private endpoint subnet, shared `privatelink.fabric.microsoft.com` private DNS zone ID, and connectivity resource group ID, supplied from the deployment environment, variable group, or upstream Terraform outputs. Never commit `.tfvars` containing tenant, subscription, principal, subnet, DNS-zone, or resource IDs.

Use `examples/databricks-onelake-baseline` as the starting shape for Databricks. Supply the approved Premium SKU and region, the caller-managed VNet and subnet IDs, explicit outbound route, the Fabric workspace and item GUIDs of the OneLake target, and the OneLake global, regional, or workspace-private DFS host required by the network and residency design.

Private-link settings are needed only when a workspace sets `private_link`. Outbound allowlists, gateway IDs, and `git_outbound_default_action = "Deny"` are accepted only when `enable_network_restrictions = true`, preventing configuration that Terraform would otherwise ignore or that the Fabric API would reject.

Set `enable_preview_domain_workspace_assignment = true` only after approving preview use and configuring the root Fabric provider with `preview = true`.

## 5. Plan and Review

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
terraform test -test-directory=tests/unit
terraform plan -out main.tfplan
```

`terraform test -test-directory=tests/unit` runs the mocked unit suite where one exists; plain `terraform test` only searches `tests/` itself and would discover no tests.

Review which workspaces opt into `enable_network_restrictions`, that no broad role assignment exists, and that all outbound exceptions are justified. Confirm that each workspace's `git_outbound_default_action` matches its source-control and data-classification requirements.

## 6. Apply Without Lockout

For each workspace with private link and network restrictions enabled, the module creates resources in this order:

1. Fabric workspace and workspace identity.
2. Fabric workspace private-link service.
3. Azure private endpoint and private DNS zone group.
4. Managed private endpoints and outbound allowlists.
5. Deny-by-default outbound workspace communication policy while inbound remains available for verification.

Before applying to production, test the same sequence in a nonproduction workspace. Set `enable_network_restrictions = true` and keep `private_link_ready_for_lockdown = false` on the first apply. Verify private-endpoint approval, that the workspace FQDN resolves to private addresses, and that authorized clients can access Fabric. Then set `private_link_ready_for_lockdown = true`, review the plan, and apply the inbound denial. Verify that unauthorized networks fail. The public-access change can take up to 30 minutes.

## 7. Postdeployment Checks

- Confirm capacity assignment completed and the capacity is active.
- Confirm workspace identity provisioning and least-privilege source permissions.
- Confirm private endpoint connection approval and private DNS records.
- Test Fabric portal, OneLake DFS/blob endpoints, SQL endpoints when applicable, and deployment-agent access.
- For opted-in workspaces, verify unapproved outbound connectors, gateways, and public inbound paths fail. Verify Git succeeds when set to `Allow` or fails when explicitly set to `Deny`.
- Record workspace/domain ownership, criticality, RTO/RPO, region, and capacity chargeback.
- Decide capacity-level OneLake DR from business impact. Replication is asynchronous, billed separately, and does not cover data outside OneLake or every Fabric item.
- Confirm Databricks classic compute uses the injected subnets and has no public IP addresses.
- When root DBFS uses a customer-managed key, confirm the workspace reports it (`properties.parameters.encryption.value.keySource` is `Microsoft.Keyvault`) and that the root DBFS storage account in the managed resource group encrypts with that key.
- Confirm the Access Connector principal has only the intended Fabric workspace access.
- Configure the Unity Catalog OneLake storage credential, connection, and foreign catalog through the separately governed Databricks workload layer; verify read-only federation without copying data.
- When direct ABFS read/write is approved, test the selected OneLake endpoint and enforce one writer per table path.

## 8. Upgrading State from Pre-release Source

This section applies only to deployments created from the pre-release source before the first AVM release. This version changes resource ownership to remove AzureRM runtime requirements. Do not apply a plan that destroys and recreates existing workspaces or private endpoints solely because Terraform addresses changed. Back up state securely and record the existing ARM resource IDs before upgrading.

Fabric workspace private-link services retain their existing AzAPI address. Private endpoints previously lived under `module.workspace_private_endpoint[<workspace-key>]`; they now live at `azapi_resource.workspace_private_endpoint[<workspace-key>]`, with their DNS zone groups at `azapi_resource.workspace_private_dns_zone_group[<workspace-key>]`. Because the former module stored the zone group inside the AzureRM private-endpoint state, there is no generic module-to-resource `moved` block that safely migrates both objects.

For each affected Fabric landing-zone/workspace pair, forget the old endpoint module without deleting its Azure objects, then import both existing objects into their new addresses. The following example calls the pattern as `module.unified_data_platform`, as the examples do, and uses zone key `platform` and workspace key `management`; substitute your module name, keys and ARM IDs (`terraform state list` shows the exact addresses):

```powershell
terraform state rm 'module.unified_data_platform.module.fabric_data_landing_zone["platform"].module.workspace_private_endpoint["management"]'
terraform import 'module.unified_data_platform.module.fabric_data_landing_zone["platform"].azapi_resource.workspace_private_endpoint["management"]' '<existing-private-endpoint-arm-id>'
terraform import 'module.unified_data_platform.module.fabric_data_landing_zone["platform"].azapi_resource.workspace_private_dns_zone_group["management"]' '<existing-private-endpoint-arm-id>/privateDnsZoneGroups/fabric-workspace'
```

If a DNS zone group does not already exist, let Terraform create it instead of importing it. State removal is not resource deletion, but a failed or incomplete import must be repaired before applying. Verify the subsequent plan has no unintended replacements. This path requires real-state verification in your isolated deployment environment; mocked tests do not prove import or upgrade convergence.

The root and Fabric child now require a `location` reporting region. Add it to existing calls without replacing the independently configured per-resource locations. Explicit diagnostic names stay stable; unnamed settings now include their map key to avoid collisions, so review any planned diagnostic-setting renames.

Azure private-link resources now use the standard Fabric landing-zone `tags` input (TFFR9). Root-wide tags are combined with a Fabric zone's `tags` before passing them to that child. Move distinct legacy `workspaces.<key>.private_link.tags` values to the zone-level input; nonempty legacy values that differ from the effective zone tags are rejected rather than ignored.

For Databricks, the workspace's existing AzAPI resource moves from `module.workspace.azapi_resource.this` to `azapi_resource.this`, and the existing management lock moves to `azapi_resource.lock[0]` through the checked-in `moved` blocks. Neither move needs an AzureRM provider. These addresses are relative to each `module.databricks_data_landing_zone[<zone-key>]` instance.

A workspace that used a root DBFS customer-managed key also has the former AzureRM root-DBFS binding in state. The checked-in `removed` block (`destroy = false`) makes Terraform forget that binding rather than destroy it, because destroying it would send `Default` and return root DBFS to platform-managed keys. Terraform can process that block only with a configured AzureRM provider, which this pattern no longer declares, so the first plan stops with `The argument "features" is required` before changing anything. Remove the binding from state before that first plan; this does not change the key binding in Azure. With the example module name and Databricks zone key `platform`:

```powershell
terraform state rm 'module.unified_data_platform.module.databricks_data_landing_zone["platform"].module.workspace.azurerm_databricks_workspace_root_dbfs_customer_managed_key.this[0]'
```

`azapi_update_resource.dbfs_root_key` then adopts the requested binding. While state still references AzureRM objects, such as the former module's resource-group data source, `terraform init` downloads the AzureRM provider; those objects need no provider configuration or manual action.

If an existing workspace has a **ReadOnly** lock, remove that lock in an approved maintenance window before adopting the new DBFS update node or changing encryption or diagnostics, then restore it through Terraform. The new lock is ordered after encryption and diagnostics on initial creation, but an already-existing lock remains effective during an upgrade. Do not mistake a mocked `moved` block check for a tested live-state migration.

The root DBFS update node stays in the graph when its key is omitted so removing the key sends `Default` and returns root DBFS to platform encryption. Review this downgrade explicitly. Managed-services and managed-disk CMK removal remains unsupported by the service; do not remove those settings from existing encrypted workspaces without following the service's migration guidance.