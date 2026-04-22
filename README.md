<<<<<<< HEAD
# Azure AKS Platform Bootstrap

> Enterprise-grade Azure Kubernetes Service (AKS) platform provisioning using Terraform, GitHub Actions CI/CD, and Helm-based observability stack.

[![Terraform](https://img.shields.io/badge/Terraform-1.6+-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-AKS-0078D4?logo=microsoftazure)](https://azure.microsoft.com/)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=githubactions)](https://github.com/features/actions)
[![Helm](https://img.shields.io/badge/Helm-3.x-0F1689?logo=helm)](https://helm.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Overview

This project automates the end-to-end provisioning of a production-ready AKS platform on Microsoft Azure. It covers:

- **AKS cluster** with autoscaling node pools and private networking
- **Azure Virtual Network** with subnets, NSGs, and private endpoints
- **DevSecOps guardrails** — RBAC, Azure Key Vault integration, encryption at rest/in-transit
- **Observability stack** — Prometheus + Grafana deployed via Helm
- **CI/CD pipeline** — GitHub Actions for Terraform plan/apply with approval gates

This reflects real-world platform engineering patterns used in enterprise financial services environments.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Subscription                        │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  Resource Group: rg-platform-prod         │   │
│  │                                                            │   │
│  │  ┌──────────────────────┐   ┌──────────────────────────┐ │   │
│  │  │   VNet: 10.0.0.0/16  │   │    Azure Key Vault        │ │   │
│  │  │                      │   │   (Secrets Management)    │ │   │
│  │  │  ┌────────────────┐  │   └──────────────────────────┘ │   │
│  │  │  │ AKS Subnet     │  │                                  │   │
│  │  │  │ 10.0.1.0/24    │  │   ┌──────────────────────────┐ │   │
│  │  │  └───────┬────────┘  │   │  Azure Monitor /          │ │   │
│  │  │          │           │   │  Log Analytics Workspace  │ │   │
│  │  │  ┌───────▼────────┐  │   └──────────────────────────┘ │   │
│  │  │  │ AKS Cluster    │  │                                  │   │
│  │  │  │ (System Pool)  │  │   ┌──────────────────────────┐ │   │
│  │  │  │ (User Pool)    │  │   │  Azure Container Registry │ │   │
│  │  │  │  HPA Enabled   │  │   └──────────────────────────┘ │   │
│  │  │  └────────────────┘  │                                  │   │
│  │  └──────────────────────┘                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
azure-aks-platform-bootstrap/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml       # PR validation — Terraform plan
│       └── terraform-apply.yml      # Main branch — Terraform apply with approval
├── terraform/
│   ├── main.tf                      # Root module composition
│   ├── variables.tf                 # Input variable declarations
│   ├── outputs.tf                   # Exported values (cluster endpoint, etc.)
│   ├── providers.tf                 # AzureRM + backend configuration
│   └── modules/
│       ├── networking/              # VNet, subnets, NSGs, private endpoints
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── aks/                     # AKS cluster, node pools, RBAC, Key Vault
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── helm/
│   └── observability/               # Prometheus + Grafana Helm values
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           └── grafana-dashboard-configmap.yaml
├── scripts/
│   └── bootstrap.sh                 # One-shot cluster bootstrap script
├── ARCHITECTURE.md                  # Detailed architecture and design decisions
└── README.md
```

---

## Prerequisites

| Tool | Minimum Version |
|------|----------------|
| Terraform | `>= 1.6` |
| Azure CLI | `>= 2.55` |
| Helm | `>= 3.13` |
| kubectl | `>= 1.28` |
| GitHub CLI | `>= 2.40` |

### Required Azure Permissions

- `Contributor` on the target subscription
- `User Access Administrator` (for RBAC assignments)
- `Key Vault Administrator` (for secret provisioning)

---

## Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/<your-org>/azure-aks-platform-bootstrap.git
cd azure-aks-platform-bootstrap
```

Copy and edit the variable file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### 2. Authenticate to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 3. Initialize Terraform

```bash
cd terraform
terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=<your-storage-account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=platform/aks.tfstate"
```

### 4. Plan and Apply

```bash
terraform plan -var-file="terraform.tfvars" -out=tfplan
terraform apply tfplan
```

### 5. Configure kubectl

```bash
az aks get-credentials \
  --resource-group rg-platform-prod \
  --name aks-platform-prod \
  --overwrite-existing
kubectl get nodes
```

### 6. Deploy Observability Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install observability ./helm/observability \
  --namespace monitoring \
  --create-namespace \
  --values helm/observability/values.yaml
```

Or use the bootstrap script for a complete one-shot setup:

```bash
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh --env prod --region eastus
```

---

## CI/CD Pipeline

### Pull Request Validation (`terraform-plan.yml`)

Triggered on every PR targeting `main`:

1. Checkout and setup Terraform
2. `terraform fmt --check`
3. `terraform validate`
4. `terraform plan` — posts plan output as PR comment
5. Security scan via `tfsec`

### Production Apply (`terraform-apply.yml`)

Triggered on merge to `main` with required approval:

1. `terraform apply` using cached plan artifact
2. Post-apply smoke test (AKS API health check)
3. Slack notification on success/failure

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Service principal client ID |
| `AZURE_CLIENT_SECRET` | Service principal secret |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |
| `AZURE_TENANT_ID` | Azure AD tenant |
| `SLACK_WEBHOOK_URL` | Deployment notifications |

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Private AKS API server | Eliminates public cluster endpoint exposure |
| Azure Key Vault CSI driver | Injects secrets as volumes — no plain-text env vars |
| Workload Identity (OIDC) | Replaces legacy SP credentials in pods |
| Horizontal Pod Autoscaler | Handles traffic bursts without over-provisioning |
| Separate system/user node pools | Isolates platform workloads from application workloads |
| Azure Monitor + Prometheus | Dual-layer observability for infra and application metrics |

---

## Observability

After deploying the Helm stack:

```bash
# Access Grafana (port-forward)
kubectl port-forward svc/observability-grafana 3000:80 -n monitoring

# Default credentials (change immediately)
# Username: admin
# Password: retrieved from Key Vault secret "grafana-admin-password"
```

Pre-built dashboards included:
- **AKS Node Metrics** — CPU, memory, disk per node
- **Pod Resource Usage** — per-namespace resource consumption
- **API Server Latency** — control plane performance
- **Ingress Request Rate** — L7 traffic overview

---

## Security Posture

- All node pools use **Managed Identities** (no stored credentials)
- **Network Policies** enforced via Azure CNI
- **Pod Security Standards** — `restricted` profile on workload namespaces
- **Azure Defender for Containers** enabled
- **Encryption at rest** — Azure-managed keys with optional CMK
- **Private endpoints** for ACR and Key Vault — no public network traversal

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/your-feature`
3. Commit changes following [Conventional Commits](https://www.conventionalcommits.org/)
4. Open a PR — the Terraform plan will auto-comment with the diff

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

*Built with expertise in enterprise Azure platform engineering, AKS operations, and DevSecOps practices.*
=======
# azure-aks-platform-bootstrap
>>>>>>> e6d90f7f3f257a4d41f471b9f006e1985650cc49
