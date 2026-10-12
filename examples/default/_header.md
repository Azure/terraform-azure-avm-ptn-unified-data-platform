# Default example

This deploys the pattern with its minimum required inputs only: one data management landing zone with an F2 Fabric capacity and one Fabric data landing zone with a business domain and a single workspace. It runs without any input. The deploying identity becomes the capacity administrator and, as its creator, a workspace administrator.

No Azure Databricks landing zone, private link, or network restrictions are deployed. See the `secure-baseline` and `databricks-onelake-baseline` examples for those capabilities.

Prerequisites: the deploying identity must be a Fabric administrator (required to create Fabric domains), and the Fabric tenant must allow it to call Fabric public APIs. See the Prerequisites section of the module README.
