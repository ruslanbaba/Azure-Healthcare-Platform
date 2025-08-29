#!/bin/bash

# Azure Healthcare Platform Deployment Script
# This script automates the deployment of the Azure Healthcare Analytics Platform

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local tools=("az" "terraform" "kubectl" "helm" "docker" "jq")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and run the script again."
        exit 1
    fi
    
    log_success "All prerequisites are met"
}

# Check Azure CLI authentication
check_azure_auth() {
    log_info "Checking Azure CLI authentication..."
    
    if ! az account show &> /dev/null; then
        log_error "Azure CLI is not authenticated"
        log_info "Please run 'az login' and try again"
        exit 1
    fi
    
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    
    log_success "Authenticated to Azure subscription: $subscription_name ($subscription_id)"
}

# Validate environment variables
validate_environment() {
    log_info "Validating environment variables..."
    
    local required_vars=(
        "ARM_CLIENT_ID"
        "ARM_CLIENT_SECRET" 
        "ARM_SUBSCRIPTION_ID"
        "ARM_TENANT_ID"
        "ENVIRONMENT"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_info "Please set the missing environment variables and run the script again."
        exit 1
    fi
    
    log_success "All required environment variables are set"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd infrastructure/terraform
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init -backend-config="backend-${ENVIRONMENT}.conf"
    
    # Validate configuration
    log_info "Validating Terraform configuration..."
    terraform validate
    
    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan -var-file="environments/${ENVIRONMENT}.tfvars" -out="${ENVIRONMENT}.tfplan"
    
    # Apply deployment
    log_info "Applying Terraform deployment..."
    terraform apply -auto-approve "${ENVIRONMENT}.tfplan"
    
    # Save outputs
    log_info "Saving Terraform outputs..."
    terraform output -json > "../outputs-${ENVIRONMENT}.json"
    
    cd ../..
    
    log_success "Infrastructure deployment completed"
}

# Extract Terraform outputs
extract_outputs() {
    log_info "Extracting Terraform outputs..."
    
    local outputs_file="infrastructure/outputs-${ENVIRONMENT}.json"
    
    if [[ ! -f "$outputs_file" ]]; then
        log_error "Terraform outputs file not found: $outputs_file"
        exit 1
    fi
    
    export AKS_RESOURCE_GROUP=$(jq -r '.resource_groups.value.compute' "$outputs_file")
    export AKS_CLUSTER_NAME=$(jq -r '.aks.value.cluster_name' "$outputs_file")
    export ACR_NAME=$(jq -r '.container_registry.value.name' "$outputs_file")
    export KEY_VAULT_NAME=$(jq -r '.security.value.key_vault_name' "$outputs_file")
    export STORAGE_ACCOUNT_NAME=$(jq -r '.data_lake.value.storage_account_name' "$outputs_file")
    export WORKLOAD_IDENTITY_CLIENT_ID=$(jq -r '.aks.value.workload_identity_client_id' "$outputs_file")
    
    log_success "Terraform outputs extracted"
}

# Configure Kubernetes access
configure_kubernetes() {
    log_info "Configuring Kubernetes access..."
    
    # Get AKS credentials
    az aks get-credentials \
        --resource-group "$AKS_RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing
    
    # Verify connectivity
    if ! kubectl get nodes &> /dev/null; then
        log_error "Failed to connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Kubernetes access configured"
}

# Install Kubernetes components
install_kubernetes_components() {
    log_info "Installing Kubernetes components..."
    
    # Add Helm repositories
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add jetstack https://charts.jetstack.io
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Install NGINX Ingress Controller
    if ! helm list -n ingress-nginx | grep -q ingress-nginx; then
        log_info "Installing NGINX Ingress Controller..."
        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace \
            --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
            --wait
    else
        log_info "NGINX Ingress Controller already installed"
    fi
    
    # Install Cert-Manager
    if ! helm list -n cert-manager | grep -q cert-manager; then
        log_info "Installing Cert-Manager..."
        helm install cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --create-namespace \
            --version v1.13.3 \
            --set installCRDs=true \
            --wait
    else
        log_info "Cert-Manager already installed"
    fi
    
    # Install Prometheus and Grafana
    if ! helm list -n monitoring | grep -q prometheus; then
        log_info "Installing Prometheus and Grafana..."
        helm install prometheus prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --create-namespace \
            --set grafana.adminPassword="$(openssl rand -base64 32)" \
            --wait
    else
        log_info "Prometheus and Grafana already installed"
    fi
    
    log_success "Kubernetes components installed"
}

# Build and push application images
build_and_push_images() {
    log_info "Building and pushing application images..."
    
    # Login to ACR
    az acr login --name "$ACR_NAME"
    
    # Build and push data processor image
    log_info "Building data processor image..."
    docker build -t "$ACR_NAME.azurecr.io/data-processor:latest" applications/data-processor/
    docker push "$ACR_NAME.azurecr.io/data-processor:latest"
    
    log_success "Application images built and pushed"
}

# Deploy applications
deploy_applications() {
    log_info "Deploying applications..."
    
    # Create namespace
    kubectl create namespace healthcare-platform --dry-run=client -o yaml | kubectl apply -f -
    
    # Create values file for environment
    cat > "charts/healthcare-platform/values-${ENVIRONMENT}-generated.yaml" <<EOF
image:
  registry: ${ACR_NAME}.azurecr.io
  tag: "latest"

env:
  STORAGE_ACCOUNT_NAME: "${STORAGE_ACCOUNT_NAME}"
  KEY_VAULT_URL: "https://${KEY_VAULT_NAME}.vault.azure.net/"
  AZURE_TENANT_ID: "${ARM_TENANT_ID}"

workloadIdentity:
  enabled: true
  clientId: "${WORKLOAD_IDENTITY_CLIENT_ID}"

secrets:
  keyVaultName: "${KEY_VAULT_NAME}"

global:
  environment: "${ENVIRONMENT}"
EOF
    
    # Deploy with Helm
    helm upgrade --install healthcare-platform ./charts/healthcare-platform \
        --namespace healthcare-platform \
        --values "./charts/healthcare-platform/values.yaml" \
        --values "./charts/healthcare-platform/values-${ENVIRONMENT}-generated.yaml" \
        --wait \
        --timeout 10m
    
    log_success "Applications deployed"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check pod status
    log_info "Checking pod status..."
    kubectl get pods -n healthcare-platform
    
    # Wait for pods to be ready
    kubectl wait --for=condition=Ready pods --all -n healthcare-platform --timeout=300s
    
    # Check services
    log_info "Checking services..."
    kubectl get services -n healthcare-platform
    
    # Check ingress
    log_info "Checking ingress..."
    kubectl get ingress -n healthcare-platform
    
    log_success "Deployment verification completed"
}

# Print deployment summary
print_summary() {
    log_info "Deployment Summary"
    echo "=================="
    echo "Environment: $ENVIRONMENT"
    echo "AKS Cluster: $AKS_CLUSTER_NAME"
    echo "Resource Group: $AKS_RESOURCE_GROUP"
    echo "Container Registry: $ACR_NAME"
    echo "Key Vault: $KEY_VAULT_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo ""
    
    # Get external IP
    local external_ip
    external_ip=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")
    echo "External IP: $external_ip"
    
    # Get Grafana password
    local grafana_password
    grafana_password=$(kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode 2>/dev/null || echo "Not available")
    echo "Grafana Password: $grafana_password"
    
    echo ""
    log_success "Deployment completed successfully!"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f "charts/healthcare-platform/values-${ENVIRONMENT}-generated.yaml"
}

# Main execution
main() {
    # Set default environment if not provided
    ENVIRONMENT=${ENVIRONMENT:-"dev"}
    
    log_info "Starting Azure Healthcare Platform deployment for environment: $ENVIRONMENT"
    
    # Run deployment steps
    check_prerequisites
    check_azure_auth
    validate_environment
    deploy_infrastructure
    extract_outputs
    configure_kubernetes
    install_kubernetes_components
    build_and_push_images
    deploy_applications
    verify_deployment
    print_summary
    cleanup
    
    log_success "Deployment completed successfully!"
}

# Trap for cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
