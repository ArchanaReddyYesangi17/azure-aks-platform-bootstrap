# Architecture & Design Reference

## Table of Contents

1. [Platform Overview](#platform-overview)
2. [Networking Design](#networking-design)
3. [AKS Cluster Design](#aks-cluster-design)
4. [Security Architecture](#security-architecture)
5. [Observability Stack](#observability-stack)
6. [CI/CD Design](#cicd-design)
7. [State Management](#state-management)
8. [Disaster Recovery](#disaster-recovery)

---

## Platform Overview

This platform is designed around three core principles:

- **Security by Default** — every resource is private-by-default with least-privilege access
- **GitOps-Driven** — all infrastructure changes flow through version-controlled pipelines
- **Observable at Every Layer** — from node metrics to application traces

### Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| IaC | Terraform 1.6+ | Declarative infrastructure provisioning |
| Cloud | Microsoft Azure | Primary cloud provider |
| Orchestration | AKS (Kubernetes 1.28+) | Container workload management |
| Networking | Azure CNI | Pod-native VNet integration |
| Secrets | Azure Key Vault + CSI Driver | Zero-secret-in-code approach |
| CI/CD | GitHub Actions | Pipeline automation |
| Package Management | Helm 3 | Kubernetes application lifecycle |
| Metrics | Prometheus + Grafana | Real-time monitoring and dashboards |
| Logging | Azure Monitor + Log Analytics | Centralized log aggregation |

---

## Networking Design

### VNet Layout

```
VNet: 10.0.0.0/16
│
├── Subnet: aks-nodes        10.0.1.0/24   (AKS node pool NICs)
├── Subnet: aks-pods         10.0.2.0/23   (Azure CNI pod IPs)
├── Subnet: private-endpoints 10.0.4.0/24  (Key Vault, ACR, etc.)
├── Subnet: ingress          10.0.5.0/24   (Internal Load Balancer)
└── Subnet: bastion          10.0.6.0/27   (Azure Bastion — jump access)
```

### Network Security Groups

Each subnet has a dedicated NSG with explicit allow/deny rules:

| NSG Rule | Direction | Priority | Action | Purpose |
|----------|-----------|----------|--------|---------|
| AllowKubeAPIServer | Inbound | 100 | Allow | Control plane → nodes |
| AllowInternalLB | Inbound | 200 | Allow | Ingress controller health probes |
| AllowVNetInternal | Inbound | 300 | Allow | Pod-to-pod within VNet |
| DenyAllInbound | Inbound | 4096 | Deny | Explicit deny-all baseline |
| AllowInternetEgress | Outbound | 100 | Allow | Image pulls (via ACR private endpoint) |
| DenyPublicEgress | Outbound | 200 | Deny | Block direct internet egress |

### Private Endpoints

The following services are accessed exclusively via private endpoints:

- **Azure Container Registry** — image pulls never traverse public internet
- **Azure Key Vault** — secret access fully private
- **Azure Monitor ingestion** — telemetry stays on Azure backbone

---

## AKS Cluster Design

### Node Pool Strategy

| Pool | VM SKU | Min | Max | Taints | Purpose |
|------|--------|-----|-----|--------|---------|
| `system` | Standard_D4s_v5 | 2 | 5 | `CriticalAddonsOnly=true:NoSchedule` | DNS, metrics-server, CSI drivers |
| `workload` | Standard_D8s_v5 | 2 | 20 | None | Application and API workloads |
| `data` | Standard_E8s_v5 | 1 | 10 | `workload=data:NoSchedule` | Memory-intensive data processing |

### Autoscaling Configuration

```yaml
# Cluster Autoscaler profile
balance-similar-node-groups: "true"
scale-down-delay-after-add: "10m"
scale-down-unneeded-time: "10m"
max-graceful-termination-sec: "600"

# HPA defaults applied to all Deployments
targetCPUUtilizationPercentage: 70
targetMemoryUtilizationPercentage: 80
```

### Identity and RBAC

- **Cluster Identity**: User-assigned Managed Identity (no client secret rotation required)
- **Kubelet Identity**: Separate managed identity for node-level operations
- **Workload Identity**: OIDC federation for pod-level Azure SDK authentication
- **RBAC**: Kubernetes RBAC integrated with Azure AD groups

```
Azure AD Group: platform-admins    → cluster-admin ClusterRole
Azure AD Group: developers         → edit Role (per namespace)
Azure AD Group: readonly           → view ClusterRole
```

---

## Security Architecture

### Defense-in-Depth Layers

```
Layer 1: Network        → Private cluster, NSGs, Private Endpoints, no public IPs
Layer 2: Identity       → Managed Identities, OIDC, no stored credentials
Layer 3: Secrets        → Key Vault + CSI Driver, secret rotation automation
Layer 4: Workload       → Pod Security Standards (restricted), Network Policies
Layer 5: Supply Chain   → ACR image scanning, signed images (Notation)
Layer 6: Audit          → Azure Monitor, Diagnostic Settings, Kubernetes audit logs
```

### Secret Lifecycle

```
Developer commits code
        │
        ▼
GitHub Actions pipeline
        │
        ▼
  Reads secrets from        ←──── Azure Key Vault (RBAC-gated)
  Key Vault via OIDC
        │
        ▼
  Terraform provisioning
        │
        ▼
  CSI Secret Store Driver   ←──── Mounts secrets as volumes in pods
        │
        ▼
  Application reads         ←──── Via file mount or env injection
  secrets at runtime               (never stored in container image)
```

### Encryption

| Data | Encryption | Key Management |
|------|-----------|----------------|
| Disk (OS + data) | AES-256 | Platform-managed key |
| etcd (cluster state) | AES-256 | Azure-managed |
| Secrets in Key Vault | RSA-2048 | HSM-backed |
| Data in transit | TLS 1.2+ | Auto-rotated certificates |

---

## Observability Stack

### Metrics Pipeline

```
Application Pods
     │ (Prometheus scrape)
     ▼
Prometheus Server ──────────────────────► Grafana Dashboards
     │                                        │
     │ (remote write)                    (alerting)
     ▼                                        │
Azure Monitor Managed Prometheus         Alertmanager
     │                                        │
     ▼                                        ▼
Log Analytics Workspace              PagerDuty / Slack
```

### Key Metrics and SLOs

| Signal | SLO Target | Alert Threshold |
|--------|-----------|----------------|
| API Server Availability | 99.9% | < 99.5% for 5m |
| Node CPU Utilization | < 80% | > 85% for 10m |
| Pod Restart Rate | < 5/hour | > 10/hour |
| Deployment Success Rate | > 99% | < 98% |
| Ingress P99 Latency | < 500ms | > 800ms for 5m |

### Log Strategy

```
Source                   Destination              Retention
─────────────────────────────────────────────────────────────
Kubernetes audit logs  → Log Analytics Workspace    90 days
Container stdout/err   → Log Analytics Workspace    30 days
Node syslog            → Log Analytics Workspace    14 days
Azure Activity logs    → Log Analytics Workspace   365 days
```

---

## CI/CD Design

### Pipeline Gates

```
Developer Push
     │
     ▼
PR Created ──► terraform fmt check
              terraform validate
              terraform plan (comment on PR)
              tfsec security scan
              OPA policy check
              ─────────────────
              Manual: Peer Review Approval
              ─────────────────
     │
     ▼
Merge to main ──► terraform apply
                  kubectl rollout status check
                  Prometheus health probe
                  ─────────────────
                  Slack notification
```

### Environment Promotion

```
feature/* branch
      │
      ▼ (PR + plan)
   develop ──► DEV environment  (auto-apply)
      │
      ▼ (PR + plan + approval)
   staging ──► STAGING environment (auto-apply)
      │
      ▼ (PR + plan + 2 approvals)
    main   ──► PROD environment  (manual trigger)
```

---

## State Management

Terraform state is stored in Azure Blob Storage with:

- **Locking**: Azure Blob lease-based state locking (prevents concurrent applies)
- **Encryption**: Storage account encryption with HTTPS-only access
- **Versioning**: Blob versioning enabled — 90-day retention for rollback
- **Access**: Managed Identity — no storage keys required

```
Storage Account: stplatformtfstate
Container:       tfstate
Key pattern:     <env>/aks.tfstate
                 <env>/networking.tfstate
```

---

## Disaster Recovery

### RTO / RPO Targets

| Component | RTO | RPO | Strategy |
|-----------|-----|-----|----------|
| AKS Cluster | 15 min | 0 (stateless) | Terraform re-apply from state |
| Persistent Volumes | 1 hour | 15 min | Azure Disk snapshots |
| Key Vault Secrets | 5 min | 0 | Geo-redundant Key Vault |
| Container Images | Immediate | 0 | ACR geo-replication |

### Backup Configuration

- **Velero** deployed for Kubernetes resource backup to Azure Blob Storage
- Backup schedule: daily full backup, 30-day retention
- Persistent Volume snapshots via Azure Disk Snapshot policies

---

## Cost Optimization

| Strategy | Implementation |
|----------|---------------|
| Right-sizing | Cluster Autoscaler — scale to zero for non-critical pools overnight |
| Spot Instances | `spot` node pool for batch/non-critical workloads (70% cost reduction) |
| Reserved Instances | 1-year RI for system node pool (40% savings) |
| Storage Tiering | Automatic lifecycle policies on Azure Blob (hot → cool → archive) |
| Dev Shutdown | Automated AKS stop/start for non-prod clusters off-hours |

---

*This architecture document reflects enterprise platform engineering standards applied in production financial services environments.*
