# Security Design

## Defaults

| Control | Default | Reason |
| --- | --- | --- |
| Workspace identity | Enabled | Removes stored source credentials and supports least privilege |
| Workspace network restrictions | Disabled | Allows each workspace to opt in based on workload compatibility and connectivity requirements |
| Inbound public access | Two-phase when network restrictions are enabled | Remains reachable for private-link verification, then changes to Deny only after explicit readiness acknowledgement |
| Outbound public access | Deny when network restrictions are enabled | Reduces exfiltration paths for protected workspaces |
| Cloud connection fallback | Deny when network restrictions are enabled | Only approved connector endpoints/workspaces are reachable |
| Gateway fallback | Deny when network restrictions are enabled | Only explicitly approved gateways are reachable |
| Git outbound access | Allow | Supports Fabric Git integration and version-control practices; restricted workspaces can explicitly select Deny |
| Domain assignment preview | Disabled | Avoids preview dependency in the baseline |
| Capacity lookup | Enforced | The root always resolves each deployed Azure capacity through the Fabric API before assigning workspaces; there is no skip-validation input |
| Tenant settings | Outside module scope | Tenant-wide controls are configured once per tenant by the tenant governance owner |
| Databricks VNet injection | Required | Places classic compute in caller-controlled networking |
| Databricks cluster public IPs | Disabled | Enables secure cluster connectivity |
| Databricks default storage firewall | Enabled | Restricts the workspace-managed storage account |
| Databricks customer-managed keys | Disabled | Opt in separately for root DBFS, managed disks, and managed services after Key Vault authorization is complete |
| Fabric workspace CMK | Disabled | Opt in per workspace with `customer_managed_key`; requires `enable_preview_workspace_encryption` and the root Fabric provider's `preview = true`, since `fabric_workspace_encryption` is a preview resource |
| Azure resource locks | Disabled | Opt in with `CanNotDelete` or `ReadOnly` on Fabric capacities and Databricks workspaces |
| AVM telemetry | Enabled | Anonymous module telemetry can be disabled per Azure-backed landing zone |
| OneLake federation identity | System-assigned Access Connector | Avoids stored credentials and supports Unity Catalog federation |
| Databricks UI/API public access | Enabled until Private Link is verified | Avoids control-plane lockout; caller can disable it for a complete private topology |

## Identity and RBAC

- Use Entra groups for human administrators, contributors, members, and viewers.
- Use service principals or managed identities for automation. Prefer federated credentials; never put client secrets in Terraform.
- Keep Fabric administrators, capacity administrators, domain administrators, and workspace administrators separate where the organization supports separation of duties.
- Capacity ARM administration members are an API exception to the group-first rule: supply a human administrator by UPN or a service principal by object ID. The API does not accept Entra groups. Use groups for domain/workspace Fabric roles and tenant-setting scope, and use `capacity_role_assignments` for ARM RBAC.
- Grant workspace identities access only to approved source subresources and data planes.
- Do not grant broad subscription roles merely to simplify deployment.
- Grant the Databricks Access Connector identity only the required Fabric workspace role. Current OneLake federation guidance requires at least Member; review this cross-platform permission explicitly.

## Network Controls

Workspace-level private link secures inbound traffic for selected workspaces without the blast radius and compatibility constraints of tenant-level private link. Each workspace gets a one-to-one Fabric private-link service and can have multiple private endpoints. The module uses the ALZ connectivity-owned `privatelink.fabric.microsoft.com` zone and a caller-supplied subnet. Set `enable_network_restrictions = true` only after validating workload compatibility. Inbound denial is a required second phase for an opted-in workspace: keep `private_link_ready_for_lockdown = false` while verifying endpoint approval, DNS, and authorized access; then set it to `true` and apply again.

`private_link_ready_for_lockdown` is an operator attestation, not an automated health check. Terraform resource ordering proves that requested resources were created; it cannot prove DNS behavior from every client network or successful user and pipeline access. The deployment review must retain evidence of endpoint approval, private DNS resolution, and authorized-path tests before changing the value to `true`.

Reserve at least ten subnet IP addresses per workspace private endpoint; Fabric currently consumes five and Microsoft recommends room for growth. Validate DNS resolution from every authorized network before denying public access.

When enabled, outbound access protection blocks all public connections first. Add only narrowly scoped managed private endpoints, hostname patterns, target workspaces, and gateway IDs. Wildcard endpoints require security review; do not use a catch-all wildcard.

Git integration is a software-delivery control rather than a general data-egress path. The module explicitly defaults `git_outbound_default_action` to `Allow` so teams can use supported Git integration, reviews, branching, and deployment workflows. Set it to `Deny` for workspaces whose risk classification or operating model prohibits Git, and protect connected repositories with least privilege, branch policies, and workload identity federation where supported.

Azure Databricks uses two dedicated caller-managed subnets with NSGs and defaults `no_public_ip` to `true`. The setting is parameterized for approved exceptions; changing an existing non-VNet-injected workspace from `true` to `false` is not supported by Azure. Explicit outbound connectivity is an ALZ networking prerequisite; subnet CIDRs, NAT/firewall routing, DNS, and service-tag rules remain caller-owned. Disabling the Databricks public UI/API requires a complete, tested Private Link topology, including browser authentication where interactive SSO is required.

Databricks customer-managed keys have separate control paths. Managed-services and managed-disk keys bind directly to the workspace, while root DBFS uses a dedicated binding resource. Managed-disk and managed-services keys must be versioned Key Vault key URLs (`https://<vault>.vault.azure.net/keys/<name>/<version>`), because the Databricks workspace encryption API needs an explicit key version for those surfaces; the module rejects versionless URLs for them at plan time, and `managed_disk_rotation_to_latest_version_enabled` follows new managed-disk key versions afterwards. The root DBFS key accepts a versioned or versionless URL. Key URLs select the vault and key; the legacy managed-disk and managed-services vault-ID hints do not affect encryption or grant access and must not be supplied. Each surface needs **Key Vault Crypto Service Encryption User**, or get/wrapKey/unwrapKey, for a different identity: the workspace storage account identity for root DBFS (see below), the disk encryption set identity (`workspace_managed_disk_identity`) for managed disks after the workspace is created, and the AzureDatabricks first-party application for managed services before it is created. Removing managed-services or managed-disk CMK from an existing workspace is not supported; replacement may be required.

Databricks diagnostic settings are created by this module as `Microsoft.Insights/diagnosticSettings` through AzAPI, so requested log categories and groups, metric categories, each entry's `enabled` flag, every destination, and `log_analytics_destination_type` are sent to Azure exactly as configured. Diagnostic-settings storage retention (`retention_policy`) is rejected at plan time: Azure Monitor retired it on 30 September 2025. Set retention on the Log Analytics tables, or use an Azure Storage lifecycle management policy for storage destinations.

For individual log selections, the module reads the workspace's available categories and explicitly disables every unselected category, including categories removed from configuration. Category-group settings stay group-based. Empty metrics are sent as `[]`, and log and metric lists are matched by category identity so response ordering does not cause repeat-plan changes.

Unnamed diagnostic settings receive stable, map-key-derived names; explicit and generated names must be unique case-insensitively. The public `AzureDiagnostics` destination option is translated to ARM `null`; `Dedicated` is sent unchanged. Legacy CMK vault ARM-ID hints are retained only as rejection sentinels so Terraform cannot silently discard them during object conversion.

Root DBFS binding uses a separate `azapi_update_resource` after workspace identity preparation. AzAPI 2.12 and 2.13 do not expose `ignore_body_changes` on that resource type. The workspace's `ignore_body_changes` configuration therefore applies only to the owning `azapi_resource`, not to DBFS binding updates. This provider/specification mismatch must be resolved with AzAPI/AVM before claiming full TFFR8 compliance; unsupported arguments are not invented or silently ignored.

The workspace resource itself never sends `parameters.encryption`. Azure rejects it in a workspace create request (`InvalidEncryptionConfiguration`, observed in a live deployment), so only the separate binding carries it. A later workspace update omits the parameter and keeps the existing binding; the integration test verifies this with a tags-only update.

Databricks creates the workspace storage account identity only when the workspace is prepared for encryption, and Microsoft's documented order grants that identity **Key Vault Crypto Service Encryption User** before the key is bound. `databricks_customer_managed_keys.dbfs_root_key_role_assignment` lets the module create that grant itself, scoped to the root DBFS key rather than the whole vault, between preparation and binding, so one apply produces an encrypted workspace. It needs an Azure RBAC vault and a deploying identity with `Microsoft.Authorization/roleAssignments/write` on the key. A new grant takes a while to reach Key Vault. Until it does, the binding can fail with `KeyVaultAuthenticationFailure`, or with `ApplicationUpdateFail` when Databricks cannot update its managed storage account; the module retries both by default until the binding's timeout, so a genuinely misconfigured key fails only then. AzAPI retries only failed HTTP responses, so if the failure is reported while a long-running operation is polled, apply again.

The grant keeps its original body during workspace updates. Whenever Terraform replaces the workspace, including with `-replace`, it also replaces the grant for the new storage identity and binds the key again. If the workspace is deleted outside Terraform, Terraform only recreates the workspace, so also replace the grant (`terraform apply -replace` on its address). ARM allows one assignment per scope, principal, and role: if the storage identity already holds this role on the key itself, delete that assignment before opting in. A vault-level grant does not conflict, and a working one makes the input unnecessary. A new version of the same key keeps the grant. Pointing root DBFS at a different key or vault replaces the grant, and Terraform deletes the old key's grant before binding the new key while the storage account still uses the old one. For such a change, first grant the storage identity this role on the old vault yourself, and remove that temporary grant after the apply. Removing `dbfs_root_key_role_assignment` deletes the grant. If the key stays in use, grant the role at vault scope first, or remove the grant from Terraform state (`terraform state rm`) to leave it in Azure.

Fabric workspace CMK is opt-in per workspace through `customer_managed_key`, gated behind `enable_preview_workspace_encryption` and the root Fabric provider's `preview = true`. Enable **Apply customer-managed keys** in the tenant, create the **Fabric Platform CMK** service principal (application ID `61d6811f-7544-4e75-a1e6-1c59c0383311`), and grant it **Key Vault Crypto Service Encryption User** or equivalent get/wrapKey/unwrapKey permissions. Authorizing only the capacity, workspace, or deployment identity does not satisfy this prerequisite. Supply a versionless RSA/RSA-HSM key identifier and enable vault soft delete and purge protection. Changing `key_identifier` rotates the customer-managed key. Removing `customer_managed_key` disables the workspace's customer-managed encryption and returns supported content to Microsoft-managed encryption; review this downgrade before applying it. See [Microsoft's CMK setup and disablement guidance](https://learn.microsoft.com/fabric/security/workspace-customer-managed-keys).

OneLake endpoint selection is parameterized because global, regional, and workspace-private FQDNs have different residency and routing implications. Federation is read-only. Direct ABFS writes require an approved single-writer strategy per table path and separately provisioned authentication; this module never accepts secrets.

## Important Limitations

- Outbound protection supports only listed Fabric item types and F SKUs in supported regions. Unsupported artifacts prevent enablement.
- Fabric external data sharing is incompatible with workspace outbound protection at the time of writing.
- Private link and outbound data-connection rules can require API-based configuration rather than portal configuration.
- Cross-tenant OneLake shortcuts and sharing do not traverse Fabric private link.
- OneLake catalog Govern has private-link limitations documented by Microsoft.
- Managed private endpoints require approval at the destination resource.
- Fabric workspace CMK protects supported workspace content, including OneLake data, and is now automated through the preview `fabric_workspace_encryption` resource; the tenant-wide CMK setting, the Fabric Platform CMK service principal, and its Key Vault permissions must still be configured before enabling `customer_managed_key`. Use versionless RSA/RSA-HSM key identifiers, enable soft delete and purge protection, and verify every item in the workspace is supported before enablement.
- OneLake federation requires supported Databricks Runtime/SQL Warehouse versions and Fabric tenant/workspace settings. These control-plane prerequisites cannot be proved by an Azure plan.
- The first Databricks module does not create front-end, browser-authentication, back-end, or serverless Private Link resources; public UI/API access must not be disabled until those dependencies are deployed and tested externally.
- Fabric tenant settings are tenant-wide and require a Fabric administrator. They are configured outside this module, once per Fabric tenant, before any DMLZ or Fabric DLZ deploys. See [Prerequisites](../README.md#prerequisites) for the required settings.

## State and Pipeline Security

- Use a private, encrypted Azure Storage backend with blob versioning, soft delete, RBAC, and state locking.
- Separate plan and apply identities. Require review and approval for production apply.
- Run static analysis and policy checks on the saved plan.
- Do not emit provider environment variables, tokens, IDs, or state in CI logs.
- Execute post-lockdown operations from an approved network path. Set `FABRIC_USE_WORKSPACE_PRIVATE_LINK_ENDPOINT=true` only where provider routing and DNS have been validated.