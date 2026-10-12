# Secure baseline example

This deploys a Fabric capacity, a business domain, and a management workspace with workspace-level private link. It runs without any input: stand-ins for the ALZ connectivity resources a production deployment passes in by resource ID (a resource group, a virtual network with a private endpoint subnet, and a `privatelink.fabric.microsoft.com` private DNS zone linked to that network) are created with AzAPI.

Deny-by-default outbound controls and the two-phase inbound lockdown stay disabled by default. Enable `enable_workspace_network_restrictions` first, and set `private_link_ready_for_lockdown` only after the private endpoint and private DNS resolution are verified; see `docs/deployment.md` in the repository. Optional group object IDs grant Fabric domain and workspace administration to Entra groups.

Prerequisites: in addition to those of the `default` example, the Fabric tenant setting "Configure workspace-level inbound network rules" must be enabled, and `Microsoft.Fabric` must be registered or re-registered in the subscription.
