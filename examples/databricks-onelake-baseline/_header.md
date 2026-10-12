# Databricks and OneLake baseline example

This deploys the Fabric landing zones together with a sibling Azure Databricks data landing zone that uses OneLake as the shared analytical layer. It runs without any input. The example creates, with AzAPI, the prerequisites a production deployment passes in by resource ID: a virtual network with two subnets delegated to `Microsoft.Databricks/workspaces`, a network security group, a NAT gateway for explicit outbound connectivity (cluster nodes have no public IP addresses), and a Log Analytics workspace for Databricks diagnostics. A Fabric Lakehouse created in the pattern's workspace is the OneLake target.

The pattern deploys the Premium Databricks workspace with VNet injection and the Access Connector whose managed identity authenticates to OneLake. Granting that identity Fabric access and configuring Unity Catalog remain deployment-time steps; see the Prerequisites section of the module README.

Prerequisites: in addition to those of the `default` example, the Fabric tenant setting "Users can access data stored in OneLake with apps external to Fabric" must be enabled for Databricks to reach OneLake.
