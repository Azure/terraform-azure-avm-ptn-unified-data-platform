locals {
  network_restricted_workspaces = {
    for key, workspace in var.workspaces : key => workspace
    if workspace.enable_network_restrictions
  }

  private_link_workspaces = {
    for key, workspace in var.workspaces : key => workspace.private_link
    if workspace.private_link != null
  }

  # Keys are JSON-encoded [workspace_key, assignment_key]/[workspace_key, endpoint_key] pairs
  # rather than a "${workspace_key}-${assignment_key}" string join. A plain "-" join is
  # ambiguous and can silently collide and overwrite entries: workspace "sales-west" with
  # assignment "reader" produces the same joined key ("sales-west-reader") as workspace
  # "sales" with assignment "west-reader". jsonencode of the two-element list escapes both
  # strings unambiguously, so two different (workspace_key, key) pairs can never produce the
  # same encoded key.
  workspace_role_assignments = merge({}, [
    for workspace_key, workspace in var.workspaces : {
      for assignment_key, assignment in workspace.role_assignments : jsonencode([workspace_key, assignment_key]) => merge(assignment, {
        workspace_key = workspace_key
      })
    }
  ]...)

  managed_private_endpoints = merge({}, [
    for workspace_key, workspace in var.workspaces : {
      for endpoint_key, endpoint in workspace.managed_private_endpoints : jsonencode([workspace_key, endpoint_key]) => merge(endpoint, {
        workspace_key = workspace_key
      })
    }
  ]...)
}
