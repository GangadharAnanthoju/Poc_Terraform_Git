# GitHub Actions + Azure OIDC Setup Guide

Terraform CI/CD using GitHub Actions with Azure User-Assigned Managed Identity (UAMI) and OIDC federated credentials — no client secrets required.

---

## Architecture

```
GitHub Actions (ubuntu-latest)
    │
    │  OIDC token (JWT) issued per run
    ▼
Azure AD (Entra ID)
    │
    │  Validates token against federated credential
    ▼
User-Assigned Managed Identity (UAMI)
    │
    │  RBAC roles grant access
    ▼
Azure Resources (subscription, storage account)
```

### Branch → Pipeline Mapping

```
feature/* ──► PR into dev ──► terraform-nonprod.yml ──► Plan + Deploy DEV
                                                          (environment: dev)

dev ──────────────────────► terraform-nonprod.yml ──► Plan + Deploy DEV

dev ──► merge into prod ──► terraform-prod.yml ──────► Plan + Deploy PROD
                                                        (environment: prod)
```

---

## One-Time Azure Setup

> Run once per UAMI. Reuse the same UAMI across multiple repos by adding more federated credentials.

### 1. Create Resource Group for Identities

```powershell
az group create --name "rg-github-identities" --location "eastus"
```

### 2. Create UAMI

```powershell
az identity create `
  --name "uami-sysint-github-actions-eastus" `
  --resource-group "rg-sysint-ideindity-eastus"
```

Save `clientId` and `principalId` from the output.

### 3. Assign RBAC Roles

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

## Per-Repo Setup

Repeat these steps for each new repository.

### Step 1 — Add Federated Credentials

Each job type needs its own federated credential because the subject claim differs:

| Job type | Subject claim |
|---|---|
| Push to `dev` branch | `repo:<org>/<repo>:ref:refs/heads/dev` |
| Job with `environment: dev` | `repo:<org>/<repo>:environment:dev` |
| Job with `environment: prod` | `repo:<org>/<repo>:environment:prod` |

```powershell
# For plan job (branch-based)
az identity federated-credential create `
  --identity-name "uami-sysint-github-actions-eastus" `
  --resource-group "rg-sysint-ideindity-eastus" `
  --name "github-nonprod-<repo-name>" `
  --issuer "https://token.actions.githubusercontent.com" `
  --subject "repo:<org>/<repo>:ref:refs/heads/dev" `
  --audiences "api://AzureADTokenExchange"

# For deploy-dev job (environment-based)
az identity federated-credential create `
  --identity-name "uami-sysint-github-actions-eastus" `
  --resource-group "rg-sysint-ideindity-eastus" `
  --name "github-dev-environment-<repo-name>" `
  --issuer "https://token.actions.githubusercontent.com" `
  --subject "repo:<org>/<repo>:environment:dev" `
  --audiences "api://AzureADTokenExchange"

# For deploy-prod job (environment-based)
az identity federated-credential create `
  --identity-name "uami-sysint-github-actions-eastus" `
  --resource-group "rg-sysint-ideindity-eastus" `
  --name "github-prod-environment-<repo-name>" `
  --issuer "https://token.actions.githubusercontent.com" `
  --subject "repo:<org>/<repo>:environment:prod" `
  --audiences "api://AzureADTokenExchange"
```

### Step 2 — GitHub Repository Secrets

**Settings → Secrets and variables → Actions → Repository secrets**

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | `clientId` of the UAMI |
| `AZURE_TENANT_ID` | Azure tenant id |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription id |

> Add at **repository level** — not environment level. The plan job has no environment and cannot read environment-level secrets.

### Step 3 — GitHub Environments

**Settings → Environments → New environment**

| Environment | Required reviewers | Notes |
|---|---|---|
| `dev` | None | Auto-deploys on push |
| `prod` | Yes — add yourself | Manual approval gate before deploy |

### Step 4 — Branch Setup

```powershell
# On first setup
git checkout -b dev
git push -u origin dev

git checkout -b prod
git push -u origin prod

# Set dev as default branch
# GitHub → Settings → General → Default branch → dev
```

### Step 5 — Copy Workflow Files

Copy `.github/workflows/terraform-nonprod.yml` and `.github/workflows/terraform-prod.yml` from this repo into the new repo. No changes needed — secrets and environment names are already parameterised.

---

## Key Concepts

### Why UAMI over App Registration + SP?

| | App Registration + SP | UAMI |
|---|---|---|
| App Registration needed | Yes | No |
| Azure resource | No (Entra ID only) | Yes (lives in resource group) |
| Reusable across repos | Yes (add more fed creds) | Yes (add more fed creds) |
| Token lifetime | 1 hour | 24 hours |

### Why two federated credentials per repo?

GitHub changes the subject claim based on the job context:
- Jobs without `environment:` → subject is the **branch ref**
- Jobs with `environment:` → subject is the **environment name**

Azure validates the subject exactly — one credential cannot cover both.

### Why secrets at repo level not environment level?

The `plan` job runs without a GitHub environment context. Environment-level secrets are only accessible to jobs that declare `environment:`. Storing at repo level makes secrets available to all jobs in the workflow.

### Audience must be `api://AzureADTokenExchange`

GitHub Actions always sends `api://AzureADTokenExchange`. If the federated credential was created with `api://AzureADTokenCredential` it will fail with AADSTS700212.

---

## Checklist for New Repo

```
Azure
  ☐ 3 federated credentials added (branch, dev env, prod env)

GitHub
  ☐ Repository secrets added (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)
  ☐ Environment "dev" created (no reviewers)
  ☐ Environment "prod" created (required reviewer)
  ☐ Default branch set to "dev"
  ☐ Branch protection on "prod" (require PR from dev)

Code
  ☐ .github/workflows/terraform-nonprod.yml copied
  ☐ .github/workflows/terraform-prod.yml copied
  ☐ .gitignore includes .terraform/ and *.tfstate
  ☐ env/dev.tfvars and env/prod.tfvars present
```
