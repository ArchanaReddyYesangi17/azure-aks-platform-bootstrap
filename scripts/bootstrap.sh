#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for AKS Platform
# Usage: ./bootstrap.sh --env <dev|staging|prod> --region <azure-region>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
ENV=""
REGION="eastus"
SKIP_HELM=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --env       Environment to deploy (dev|staging|prod)  [required]
  --region    Azure region                               [default: eastus]
  --skip-helm Skip Helm observability stack deployment
  -h, --help  Show this help message
EOF
  exit 1
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)    ENV="$2";    shift 2 ;;
      --region) REGION="$2"; shift 2 ;;
      --skip-helm) SKIP_HELM=true; shift ;;
      -h|--help) usage ;;
      *) error "Unknown argument: $1" ;;
    esac
  done
  [[ -z "$ENV" ]] && error "--env is required"
  [[ "$ENV" =~ ^(dev|staging|prod)$ ]] || error "Invalid env: $ENV"
}

check_prerequisites() {
  log "Checking prerequisites..."
  local missing=()
  for tool in az terraform helm kubectl; do
    command -v "$tool" &>/dev/null || missing+=("$tool")
  done
  [[ ${#missing[@]} -gt 0 ]] && error "Missing tools: ${missing[*]}"

  az account show &>/dev/null || error "Not logged in to Azure. Run: az login"
  log "Prerequisites OK"
}

terraform_deploy() {
  log "Deploying Terraform for environment: $ENV"
  cd "$ROOT_DIR/terraform"

  terraform init \
    -backend-config="key=${ENV}/aks.tfstate" \
    -reconfigure

  terraform plan \
    -var-file="environments/${ENV}.tfvars" \
    -var="location=${REGION}" \
    -out=tfplan

  log "Applying Terraform plan..."
  terraform apply tfplan
  log "Terraform apply complete"
}

configure_kubectl() {
  log "Configuring kubectl..."
  local rg
  rg=$(terraform -chdir="$ROOT_DIR/terraform" output -raw resource_group_name)
  local cluster
  cluster=$(terraform -chdir="$ROOT_DIR/terraform" output -raw aks_cluster_name)

  az aks get-credentials \
    --resource-group "$rg" \
    --name "$cluster" \
    --overwrite-existing

  kubectl get nodes
  log "kubectl configured"
}

deploy_observability() {
  if [[ "$SKIP_HELM" == "true" ]]; then
    log "Skipping Helm deployment (--skip-helm)"
    return
  fi

  log "Deploying observability stack..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update

  helm upgrade --install observability "$ROOT_DIR/helm/observability" \
    --namespace monitoring \
    --create-namespace \
    --values "$ROOT_DIR/helm/observability/values.yaml" \
    --wait \
    --timeout 10m

  log "Observability stack deployed"
  log "Access Grafana: kubectl port-forward svc/observability-grafana 3000:80 -n monitoring"
}

main() {
  parse_args "$@"
  check_prerequisites
  terraform_deploy
  configure_kubectl
  deploy_observability
  log "Bootstrap complete for environment: $ENV"
}

main "$@"
