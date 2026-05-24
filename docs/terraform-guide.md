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
9. [Quick Command Reference](#9-quick-command-reference)

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
application_name = "first"
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

### How to use per-environment files

```powershell
terraform plan -var-file ./env/dev.tfvars
terraform plan -var-file ./env/prod.tfvars
terraform plan -var-file ./env/dev.tfvars -var "instance_count=9"
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
$env:TF_VAR_api_key = "mysecret"
terraform apply -var-file ./env/dev.tfvars
```

---

## 5. Validation

Validation blocks run **before** Terraform contacts any provider:

```hcl
variable "application_name" {
  type = string
  validation {
    condition     = length(var.application_name) <= 12
    error_message = "Application Name must be less than or equal to 12 characters"
  }
}
```

---

## 6. Loops — count, for_each, conditional

### `count` — repeat N times
```hcl
resource "random_string" "list" {
  count   = length(var.regions)
  length  = 6
  upper   = false
  special = false
}
```

### `for_each` — iterate a map or set
```hcl
resource "random_string" "map" {
  for_each = var.region_instance_count
  length   = 6
  upper    = false
  special  = false
}
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

---

## 7. Modules

### Registry modules (remote)
```hcl
module "alpha" {
  source  = "hashicorp/module/random"
  version = "1.0.0"
}
```

### Local modules (path-based)
```hcl
module "charlie" {
  source = "./modules/rando"
  length = 8
}
```

---

## 8. Outputs

```hcl
output "application_name" {
  value = var.application_name
}

output "primary_region" {
  value = var.regions[0]
}
```

```powershell
terraform output application_name
```

---

## 9. Quick Command Reference

```powershell
terraform init
terraform plan -var-file ./env/dev.tfvars
terraform apply -var-file ./env/dev.tfvars
terraform apply -var-file ./env/prod.tfvars
terraform output application_name
terraform destroy

# Key concepts
variables.tf      → DECLARE variables
terraform.tfvars  → SET values (auto-loaded)
env/*.tfvars      → SET environment-specific values (-var-file)
TF_VAR_*          → SET via shell (highest priority, secrets)
locals {}         → COMPUTE intermediate values
outputs.tf        → EXPOSE values after apply
modules/          → PACKAGE reusable resource groups
```
