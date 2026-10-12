# Global tflint override merged onto avm.tflint.hcl for the repository root
# scope by Avm.Authoring's `avm lint` (see Merge-AvmTflintConfig.ps1 in the
# Avm.Authoring PowerShell module - this filename, not .tflint.hcl, is what
# it actually reads for overrides).
#
# RMFR7 (the spec avm_output_resource_id_required enforces) is tagged
# Class-Resource only, not Class-Pattern:
# https://azure.github.io/Azure-Verified-Modules/spec/RMFR7/
# This repository is a pattern module composing multiple heterogeneous
# resources (Fabric capacities, Fabric workspaces, Databricks workspaces,
# access connectors) with no single `resource_id` to expose.
rule "avm_output_resource_id_required" {
  enabled = false
}
