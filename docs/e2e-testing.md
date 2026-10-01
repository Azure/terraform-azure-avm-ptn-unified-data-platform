# End-to-end deployment testing (SNFR2/SNFR7)

Deployment, idempotency, and cleanup testing uses the centrally managed AVM workflow, not a repository-specific one. `.github/workflows/pr-check.yml` is an AVM managed file (synchronized by `avm sync` and `avm pre-commit`) that calls the reusable [`terraform-module.yml`](https://github.com/Azure/azure-verified-modules-tools/blob/main/.github/workflows/terraform-module.yml) workflow on every pull request. That workflow runs these jobs:

| Job | Command | Credentials | What it proves |
| --- | --- | --- | --- |
| Unit tests | `avm test unit` | none (mocked providers) | The root and every `modules/*` unit suite passes |
| PR check | `avm pr-check` | AVM test subscription over OIDC | Managed files, formatting, transforms, TFLint, Conftest policy plans of every example, AVM conventions, validation, and generated documentation are all clean |
| Integration tests | `avm test integration` | AVM test subscription over OIDC | Every `tests/integration` suite in the root and `modules/*` passes against real Azure; here, the Databricks root DBFS customer-managed key test below |
| End-to-end tests | `avm test e2e --example <name>`, one job per example | AVM test subscription over OIDC | Each example deploys, a second `plan -detailed-exitcode` reports no changes (idempotency), and the deployment is destroyed on every path (cleanup) |

The AVM test subscription and its OIDC credentials are provided centrally; module owners approve credentialed runs. Nothing in this repository stores credentials, subscription IDs, or environment-specific inputs.

## Examples deploy without input

`avm test e2e` and the policy step of `avm pr-check` run `terraform apply`/`plan` without variable files, so every example must deploy with its defaults only. Each example therefore creates its own prerequisites with AzAPI, names every resource with a random suffix, and derives the tenant and subscription from `data.azapi_client_config`:

- `examples/default` uses only the required inputs (one capacity, one business domain, one workspace).
- `examples/secure-baseline` also creates a resource group, a virtual network with a private endpoint subnet, and a `privatelink.fabric.microsoft.com` private DNS zone linked to it.
- `examples/databricks-onelake-baseline` also creates a virtual network with two subnets delegated to `Microsoft.Databricks/workspaces`, a network security group, a NAT gateway, a Log Analytics workspace, and a Fabric Lakehouse used as the OneLake target.

Each example's `tests/unit/defaults.tftest.hcl` plans the example with mocked providers and no variables, so the input-free contract is checked on every change without Azure access.

## Fabric provider authentication

The Microsoft Fabric provider reads the same `ARM_*` identity variables as AzAPI, including `ARM_CLIENT_ID`, `ARM_TENANT_ID`, and `ARM_USE_OIDC`, and requests the GitHub Actions OIDC token itself. The identity that the AVM workflow configures for AzAPI therefore also authenticates the Fabric provider, without hooks or extra variables. With a local `az login`, both providers use the Azure CLI sign-in.

## Tenant prerequisites for the test identity

Azure access alone is not sufficient: the Fabric tenant of the test identity must satisfy the Fabric items in the [README prerequisites](../README.md#prerequisites). In particular, the identity must be a Fabric administrator (required to create Fabric domains), and the tenant settings for service-principal API access, workspace-level inbound network rules, and external OneLake access must be enabled. This module treats these tenant-level settings as prerequisites and does not change them.

## Running end-to-end tests locally

With PowerShell 7.4 or later and an `az login` session for a disposable subscription whose Fabric tenant meets the prerequisites:

```powershell
Install-PSResource Avm.Authoring
Import-Module Avm.Authoring
avm test e2e --example default
```

The command runs `terraform init -upgrade`, `apply` (retrying transient capacity errors after a destroy), the idempotency `plan -detailed-exitcode`, and `destroy`. `destroy` runs whenever initialization succeeded, including after a failed apply. If `destroy` itself fails, the remaining resources must be removed manually.

## Root DBFS customer-managed key integration test

`modules/databricks-data-landing-zone/tests/integration/dbfs_root_key.tftest.hcl` checks behavior that mocked tests cannot: the order in which Azure accepts a root DBFS key, and whether the key survives later workspace updates. No example covers it, because examples deploy the whole pattern including Fabric. It runs these steps:

1. `prerequisites` creates a resource group, a virtual network with two delegated subnets and a network security group, an Azure RBAC Key Vault with purge protection and public access disabled except for trusted Azure services, and an RSA key. No clusters start, so the test creates no outbound path.
2. `bind_dbfs_key_in_one_apply` deploys a VNet-injected premium workspace with `dbfs_root_key_role_assignment`, so one apply prepares the workspace, grants its storage identity access to the key, and binds the key.
3. `verify_binding` reads the workspace and the root DBFS storage account back from Azure and requires both to use the key.
4. `workspace_update_keeps_dbfs_key` changes only the workspace tags, a full workspace PUT, and `verify_binding_after_update` requires the key to still be in place.

Terraform destroys all of it at the end, workspace first. Because of purge protection, the deleted Key Vault stays soft-deleted for 7 days, so every run uses a new random name. A run took about 15 minutes in `swedencentral`, set in the `prerequisites` run, and costs the resources above for that time, with no Databricks clusters. The fixture keeps Key Vault public access disabled, so it also runs in tenants whose policies enforce that.

The identity needs `Contributor` and `User Access Administrator` (or `Role Based Access Control Administrator`) on the subscription, because the module assigns a role on the key. To run it locally with an `az login` session for a disposable subscription:

```powershell
Import-Module Avm.Authoring
avm test integration
```

If a run is interrupted, delete any leftover `rg-udp-dbfs-it-*` resource groups.
