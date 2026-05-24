# Terraform POC — Azure with GitHub Actions CI/CD

Terraform on Azure, deployed via GitHub Actions using **UAMI OIDC federated credentials** — no App Registration, no Service Principal, no client secrets, no secret rotation.

---

## Architecture

![CI/CD Architecture](images/Architecture.jpg)

---

## CI/CD Pipeline

| Branch | Trigger | Pipeline | Deploy target |
|---|---|---|---|
| `feature/*` | push / PR into `dev` | terraform-nonprod.yml | DEV (with approval) |
| `dev` | push | terraform-nonprod.yml | DEV (with approval) |
| `prod` | merge from `dev` | terraform-prod.yml | PROD (with approval) |

---

## GitHub Actions + Azure UAMI OIDC Setup

### What is UAMI OIDC?

A **User-Assigned Managed Identity (UAMI)** is a standalone Azure resource that acts as an identity. A **federated credential** is attached to it that trusts OIDC tokens issued by GitHub Actions.

When a workflow runs:
1. GitHub issues a short-lived signed JWT (OIDC token) for that specific run
2. Azure validates the token against the federated credential (issuer + subject + audience must all match)
3. Azure grants access based on RBAC roles assigned to the UAMI
4. No secret is stored anywhere

---

### One-Time Azure Setup

> Run once. Reuse the same UAMI across multiple repos by adding more federated credentials.

**1. Create resource group for identities**
```powershell
az group create --name "rg-github-identities" --location "eastus"
```

**2. Create UAMI**
```powershell
az identity create `
  --name "uami-sysint-github-actions-eastus" `
  --resource-group "rg-sysint-ideindity-eastus"
```
Save `clientId` and `principalId` from the output.

**3. Assign RBAC roles**
```powershell
$OID = az identity show `
  --name "uami-sysint-github-actions-eastus" `
  --resource-group "rg-sysint-ideindity-eastus" `
  --query principalId -o tsv

# Contributor on subscription
az role assignment create `
  --assignee $OID `
  --role "Contributor" `
  --scope "/subscriptions/<subscription-id>"

# Storage Blob Data Contributor for Terraform remote state
az role assignment create `
  --assignee $OID `
  --role "ba92f5b4-2d11-453d-a403-e96b0029c9fe" `
  --scope "/subscriptions/<subscription-id>/resourceGroups/<tfstate-rg>/providers/Microsoft.Storage/storageAccounts/<storage-account>"
```

---

### Per-Repo Setup

**Step 1 — Add federated credentials**

Each job type needs its own federated credential — GitHub changes the subject claim based on job context:

| Job type | Subject claim |
|---|---|
| Push to `dev` branch (plan job) | `repo:<org>/<repo>:ref:refs/heads/dev` |
| Job with `environment: dev` | `repo:<org>/<repo>:environment:dev` |
| Job with `environment: prod` | `repo:<org>/<repo>:environment:prod` |

```powershell
# Plan job (branch-based)
az identity federated-credential create `
  --identity-name "uami-sysint-github-actions-eastus" `
  --resource-group "rg-sysint-ideindity-eastus" `
  --name "github-nonprod-<repo-name>" `
  --issuer "https://token.actions.githubusercontent.com" `
  --subject "repo:<org>/<repo>:ref:refs/heads/dev" `
  --audiences "api://AzureADTokenExchange"

# Deploy-dev job (environment-based)
az identity federated-credential create `
  --identity-name "uami-sysint-github-actions-eastus" `
  --resource-group "rg-sysint-ideindity-eastus" `
  --name "github-dev-environment-<repo-name>" `
  --issuer "https://token.actions.githubusercontent.com" `
  --subject "repo:<org>/<repo>:environment:dev" `
  --audiences "api://AzureADTokenExchange"

# Deploy-prod job (environment-based)
az identity federated-credential create `
  --identity-name "uami-sysint-github-actions-eastus" `
  --resource-group "rg-sysint-ideindity-eastus" `
  --name "github-prod-environment-<repo-name>" `
  --issuer "https://token.actions.githubusercontent.com" `
  --subject "repo:<org>/<repo>:environment:prod" `
  --audiences "api://AzureADTokenExchange"
```

> Audience must be `api://AzureADTokenExchange` — GitHub Actions always sends this value.

**Step 2 — GitHub repository secrets** (repo level, not environment level)

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | `clientId` of the UAMI |
| `AZURE_TENANT_ID` | Azure tenant id |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription id |

> Store at **repository level** — the plan job has no environment context and cannot read environment-level secrets.

**Step 3 — GitHub environments**

| Environment | Required reviewers | Notes |
|---|---|---|
| `dev` | None | Auto-deploys on push |
| `prod` | Yes — add yourself | Manual approval gate |

**Step 4 — Branch setup**
```powershell
git checkout -b dev && git push -u origin dev
git checkout -b prod && git push -u origin prod
# Set default branch to dev: GitHub → Settings → General → Default branch
```

**Step 5 — Copy workflow files**

Copy `.github/workflows/terraform-nonprod.yml` and `.github/workflows/terraform-prod.yml` into the new repo — secrets and environment names are already parameterised, no changes needed.

---

### Checklist for New Repo

```
Azure
  ☐ 3 federated credentials added (branch, dev env, prod env)

GitHub
  ☐ Repository secrets added (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)
  ☐ Environment "dev" created (no reviewers)
  ☐ Environment "prod" created (required reviewer)
  ☐ Default branch set to "dev"

Code
  ☐ .github/workflows/terraform-nonprod.yml copied
  ☐ .github/workflows/terraform-prod.yml copied
  ☐ .gitignore includes .terraform/ and *.tfstate
  ☐ env/dev.tfvars and env/prod.tfvars present
```

---

## Terraform Reference

For Terraform variable types, locals, loops, modules, outputs and commands see [docs/terraform-guide.md](docs/terraform-guide.md).
