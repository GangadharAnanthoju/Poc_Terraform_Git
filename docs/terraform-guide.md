# Terraform Learning Guide (Azure Focus)

Based on the files in this repo. Every example comes directly from the code.

---

## Table of Contents

1. [Variable Types](#1-variable-types)
2. [Locals](#2-locals)
3. [Variable Files & Priority Order](#3-variable-files--priority-order)
4. [Sensitive Variables & Environment Vars](#4-sensitive-variables--environment-vars)
5. [Validation](#5-validation)
6. [Loops — count, for_each, conditional](#6-loops--count-for_each-conditional)
7. [Modules](#7-modules)
8. [Outputs](#8-outputs)
9. [Provider & Version Constraints](#9-provider--version-constraints)
10. [Remote State & Backend](#10-remote-state--backend)
11. [Implicit Dependencies](#11-implicit-dependencies)
12. [Quick Command Reference](#12-quick-command-reference)

---

## 1. Variable Types

Defined in [variables.tf](../variables.tf). Terraform supports these primitive and complex types:

### `string`
Plain text. Most common type.
```hcl
variable "application_name" {
  type = string
}
```
Value in `terraform.tfvars`:
```hcl
application_name = "terraform-poc"
```

---

### `number`
Integer or float.
```hcl
variable "instance_count" {
  type = number
}
```
Value:
```hcl
instance_count = 7
```

---

### `bool`
`true` or `false`. Used for feature flags and conditional resource creation.
```hcl
variable "enabled" {
  type = bool
}
```
Value:
```hcl
enabled = false
```

---

### `list(string)`
Ordered collection. Duplicates are allowed. Access by index (zero-based).
```hcl
variable "regions" {
  type = list(string)
}
```
Value:
```hcl
regions = ["westus", "eastus", "westus"]   # duplicates allowed
```
Access in code:
```hcl
var.regions[0]   # → "westus"
```

---

### `set(string)`
Like a list but **no duplicates, no guaranteed order**. Good for unique keys.
```hcl
variable "region_set" {
  type = set(string)
}
```
Value:
```hcl
region_set = ["westus", "eastus"]
```
> If you passed `["westus", "eastus", "westus"]` to a set, the duplicate would be silently dropped.

---

### `map(string)`
Key-value pairs. Access by key.
```hcl
variable "region_instance_count" {
  type = map(string)
}
```
Value:
```hcl
region_instance_count = {
  "westus" = 4
  "eastus" = 8
}
```
Access in code:
```hcl
var.region_instance_count["westus"]           # → 4
var.region_instance_count[var.regions[0]]     # dynamic key lookup
```

---

### `object`
Structured type — like a typed map. Each key has its own type.
```hcl
variable "sku_settings" {
  type = object({
    kind = string
    tier = string
  })
}
```
Value:
```hcl
sku_settings = {
  kind = "P"
  tier = "Business"
}
```
Access:
```hcl
var.sku_settings.kind   # → "P"
var.sku_settings.tier   # → "Business"
```

---

### Type Comparison Summary

| Type          | Ordered | Duplicates | Access by    | Example value                        |
|---------------|---------|------------|--------------|--------------------------------------|
| `string`      | —       | —          | —            | `"westus"`                           |
| `number`      | —       | —          | —            | `7`                                  |
| `bool`        | —       | —          | —            | `true`                               |
| `list(T)`     | Yes     | Yes        | Index `[0]`  | `["westus", "eastus"]`               |
| `set(T)`      | No      | No         | iteration    | `["westus", "eastus"]`               |
| `map(T)`      | No      | No (keys)  | Key `["k"]`  | `{ westus = 4 }`                     |
| `object({…})` | No      | —          | Attr `.kind` | `{ kind = "P", tier = "Business" }`  |

---

## 2. Locals

Locals are **computed values** that exist only within the root module. They are not inputs — you can't set them from outside.

```hcl
locals {
  environment_prefix = "${var.application_name}-${var.environment_name}-${random_string.suffix.result}"
}
```

**When to use locals vs variables:**

| Use case                              | Use        |
|---------------------------------------|------------|
| Value comes from outside (user/env)   | `variable` |
| Value computed from other values      | `local`    |
| Value used in multiple places         | `local`    |
| Value that should never be overridden | `local`    |

---

## 3. Variable Files & Priority Order

Terraform loads variable values from multiple sources. **Later sources win:**

```
Priority (lowest → highest)
──────────────────────────────────────────────────────────────
1. Default value inside variable block (variables.tf)
2. terraform.tfvars            (auto-loaded)
3. *.auto.tfvars               (auto-loaded, alphabetical order)
4. -var-file flag              (explicit, e.g. -var-file ./env/prod.tfvars)
5. -var flag                   (inline on CLI, e.g. -var "name=value")
6. TF_VAR_<name> env variable  (highest priority)
──────────────────────────────────────────────────────────────
```

### Files in this repo

```
├── terraform.tfvars        # auto-loaded — sets application_name, primary_location
├── env/
│   ├── dev.tfvars          # NOT auto-loaded — pass with -var-file
│   └── prod.tfvars         # NOT auto-loaded — pass with -var-file
```

### How to use per-environment files

```powershell
terraform plan -var-file ./env/dev.tfvars
terraform plan -var-file ./env/prod.tfvars
terraform plan -var-file ./env/dev.tfvars -var "application_name=myapp"
```

---

## 4. Sensitive Variables & Environment Vars

Mark a variable `sensitive = true` so Terraform never prints its value:

```hcl
variable "api_key" {
  type      = string
  sensitive = true
}
```

Pass sensitive values via environment variable — never store in `.tfvars`:

```powershell
# PowerShell
$env:TF_VAR_api_key = "mysecret"
terraform apply -var-file ./env/dev.tfvars
```

```bash
# Bash
export TF_VAR_api_key=mysecret
```

---

## 5. Validation

Validation blocks run **before** Terraform contacts any provider — catches bad input early:

```hcl
variable "application_name" {
  type = string
  validation {
    condition     = length(var.application_name) <= 12
    error_message = "Application Name must be less than or equal to 12 characters"
  }
}
```

Multiple conditions in one block:
```hcl
variable "instance_count" {
  type = number
  validation {
    condition     = var.instance_count >= 5 &&
                    var.instance_count <= 9 &&
                    var.instance_count % 2 != 0
    error_message = "Must be between 5 and 9 and never even!"
  }
}
```

---

## 6. Loops — count, for_each, conditional

### `count` — repeat N times
```hcl
resource "random_string" "list" {
  count   = length(var.regions)   # creates one resource per region
  length  = 6
  upper   = false
  special = false
}
# access: random_string.list[0].result
```

### `for_each` — iterate a map or set (preferred over count)
```hcl
resource "random_string" "map" {
  for_each = var.region_instance_count   # { westus=4, eastus=8 }
  length   = 6
  upper    = false
  special  = false
}
# access: random_string.map["westus"].result
# inside body: each.key → "westus", each.value → 4
```

### Conditional — create 0 or 1 resource
```hcl
resource "random_string" "if" {
  count   = var.enabled ? 1 : 0
  length  = 6
  upper   = false
  special = false
}
```

| Scenario                          | Use        |
|-----------------------------------|------------|
| Fixed count                       | `count`    |
| Iterating a map or set            | `for_each` |
| Items have meaningful unique keys | `for_each` |
| On/off toggle                     | `count`    |

> **Prefer `for_each` over `count`** for maps/sets — removing an item from the middle of a list causes `count` to re-index and destroy/recreate everything after it.

---

## 7. Modules

### Registry modules (remote)
```hcl
module "alpha" {
  source  = "hashicorp/module/random"   # <namespace>/<module>/<provider>
  version = "1.0.0"
}
```

### Local modules (path-based)
```hcl
module "charlie" {
  source = "./modules/rando"
  length = 8
}

# Read module output
module.charlie.random_string
```

| Scenario                              | Create a module? |
|---------------------------------------|-----------------|
| Same resource pattern in 3+ places    | Yes             |
| Environment-specific config only      | No — use tfvars |
| Shared infra used by multiple teams   | Yes             |
| Single resource, used once            | No              |

---

## 8. Outputs

From [outputs,tf](../outputs,tf) in this repo:

```hcl
output "application_name" {
  value = var.application_name
}

output "environment_name" {
  value = var.environment_name
}
```

Outputs that reference sensitive variables must be marked sensitive:
```hcl
output "api_key" {
  value     = var.api_key
  sensitive = true
}
```

Read after apply:
```powershell
terraform output application_name
terraform output environment_name
terraform output -json   # all outputs as JSON
```

---

## 9. Provider & Version Constraints

Defined in [versions.tf](../versions.tf):

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.3"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "d835f9fb-e4f6-4ffe-9740-e32ebdef91ff"
}
```

### Version constraint operators

| Operator | Meaning | Example | Allows |
|---|---|---|---|
| `~>` | Pessimistic — patch/minor only | `~> 4.8.0` | `4.8.x` only |
| `~>` (minor) | Pessimistic — minor only | `~> 4.8` | `4.x` where x ≥ 8 |
| `>=` | Greater than or equal | `>= 4.0` | `4.0, 4.8, 5.0` |
| `=` | Exact | `= 4.8.0` | `4.8.0` only |

`~> 4.8.0` is the safest choice for production — allows bug fixes (`4.8.1`, `4.8.2`) but blocks breaking changes (`4.9.0`).

### `.terraform.lock.hcl`

`terraform init` creates this file automatically. It records the **exact provider versions and hashes** that were downloaded:

```hcl
provider "registry.terraform.io/hashicorp/azurerm" {
  version     = "4.8.0"
  constraints = "~> 4.8.0"
  hashes = [...]
}
```

**Always commit `.terraform.lock.hcl`** — it ensures every team member and CI/CD pipeline uses the exact same provider versions. Never commit the `.terraform/` directory itself (add to `.gitignore`).

---

## 10. Remote State & Backend

Defined in [versions.tf](../versions.tf):

```hcl
backend "azurerm" {
  resource_group_name  = "rg-sysint-terraform-state-dev-eastus"
  storage_account_name = "st01terraformstate"
  container_name       = "tfstate"
  key                  = "terraform.tfstate-dev"
}
```

### What is Terraform state?

Terraform tracks every resource it creates in a **state file** (`terraform.tfstate`). It uses this to:
- Know what exists vs what the config says should exist
- Calculate the diff on every `plan`
- Know what to destroy on `terraform destroy`

### Why remote state?

| | Local state | Remote state (Azure Blob) |
|---|---|---|
| Location | `terraform.tfstate` on disk | Azure Storage Account |
| Team use | One person only | Multiple people/pipelines |
| State locking | No | Yes — prevents concurrent applies |
| Accidental deletion | Likely | Protected by Azure RBAC |
| Secret exposure | File on disk | Controlled access |

### How the backend works in this repo

```
terraform init
    ↓
Downloads providers → .terraform/
Connects to Azure Blob Storage → reads/writes terraform.tfstate-dev
    ↓
terraform plan  → reads state, calculates diff
terraform apply → applies changes, writes updated state back to blob
```

### State locking

When `terraform apply` runs, Azure Blob Storage automatically locks the state file. If another pipeline tries to run at the same time it will wait or fail — preventing two applies from corrupting the state simultaneously.

### Never commit state files

State files contain resource IDs and may contain sensitive values. They are excluded by `.gitignore`:
```
*.tfstate
*.tfstate.*
```

---

## 11. Implicit Dependencies

Terraform automatically determines the order to create resources based on **references between them**. You don't need to specify order manually.

From [main.tf](../main.tf):

```hcl
resource "random_string" "suffix1" {
  length  = 10
  upper   = false
  special = false
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.application_name}-${var.environment_name}"
  location = var.primary_location
}
```

If the resource group name referenced `random_string.suffix1.result`, Terraform would automatically create `random_string.suffix1` first — the reference creates an implicit dependency.

### Explicit dependency with `depends_on`

Use `depends_on` only when a dependency exists that Terraform cannot see through a reference:

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.application_name}-${var.environment_name}"
  location = var.primary_location

  depends_on = [random_string.suffix1]   # explicit when no reference exists
}
```

> Prefer implicit dependencies (references) over `depends_on` — they are self-documenting and Terraform can plan them more efficiently.

---

## 12. Quick Command Reference

```powershell
# Setup
terraform init                              # download providers, configure backend

# Code quality
terraform fmt                               # auto-format all .tf files
terraform validate                          # validate config syntax before plan

# Planning
terraform plan                              # preview changes (dry run)
terraform plan -var-file ./env/dev.tfvars   # plan with env-specific vars
terraform plan -out=tfplan                  # save plan to file

# Applying
terraform apply -var-file ./env/dev.tfvars
terraform apply -var-file ./env/prod.tfvars
terraform apply tfplan                      # apply a saved plan file

# Inspecting
terraform output                            # show all outputs
terraform output application_name          # show specific output
terraform output -json                      # all outputs as JSON
terraform show                              # show current state in readable form
terraform state list                        # list all resources tracked in state

# Cleanup
terraform destroy -var-file ./env/dev.tfvars
```

### File roles at a glance

```
versions.tf       → DECLARE providers, versions, backend
variables.tf      → DECLARE variables (name, type, validation)
main.tf           → DEFINE resources
outputs,tf        → EXPOSE values after apply
terraform.tfvars  → SET values (auto-loaded)
env/*.tfvars      → SET environment-specific values (manual -var-file)
TF_VAR_*          → SET via shell env (highest priority, use for secrets)
locals {}         → COMPUTE intermediate values (not settable from outside)
.terraform.lock.hcl → LOCK provider versions — always commit this
.terraform/       → downloaded providers — never commit, add to .gitignore
*.tfstate         → state files — never commit, add to .gitignore
```
