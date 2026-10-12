# Global tflint override merged onto avm.tflint_module.hcl for every
# modules/* scope by Avm.Authoring's `avm lint` (see
# Merge-AvmTflintConfig.ps1 in the Avm.Authoring PowerShell module - this
# filename, not .tflint.hcl, is what it actually reads for overrides).
#
# RMFR7 (the spec avm_output_resource_id_required enforces) is tagged
# Class-Resource only, not Class-Pattern:
# https://azure.github.io/Azure-Verified-Modules/spec/RMFR7/
# Every submodule in modules/* (data-management-landing-zone,
# databricks-data-landing-zone, and fabric-data-landing-zone) composes several
# resources rather than wrapping a single primary ARM resource type, so none of
# them have a single `resource_id` to expose.
rule "avm_output_resource_id_required" {
  enabled = false
}
