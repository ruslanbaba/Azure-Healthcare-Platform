#!/bin/bash

# IMPORTANT: This script is for CI/CD pipeline execution only
# DO NOT RUN LOCALLY - Execute via Azure DevOps Pipelines or GitHub Actions

# Comprehensive Observability Stack Deployment Script
# Deploys Prometheus, Grafana, Loki, Tempo, and AlertManager for Healthcare Platform
# Designed for cloud-native CI/CD pipeline execution

set -euo pipefail

# Color codes for CI/CD pipeline output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration for CI/CD environment
NAMESPACE="monitoring"
HEALTHCARE_NAMESPACE="healthcare-platform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="${SCRIPT_DIR}/../k8s/monitoring"

# Function to print colored output for CI/CD logs
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running in CI/CD environment
check_ci_environment() {
    if [[ -z "${AZURE_DEVOPS_BUILD_ID:-}" ]] && [[ -z "${GITHUB_ACTIONS:-}" ]] && [[ -z "${CI:-}" ]]; then
        print_error "This script must be executed in a CI/CD pipeline environment only"
        print_error "Detected environment variables:"
        print_error "  AZURE_DEVOPS_BUILD_ID: ${AZURE_DEVOPS_BUILD_ID:-not set}"
        print_error "  GITHUB_ACTIONS: ${GITHUB_ACTIONS:-not set}"
        print_error "  CI: ${CI:-not set}"
        print_error ""
        print_error "Please execute this script via:"
        print_error "  - Azure DevOps Pipelines"
        print_error "  - GitHub Actions"
        print_error "  - Other approved CI/CD platforms"
        exit 1
    fi
    
    print_success "CI/CD environment detected - proceeding with deployment"
}

# Function to verify CI/CD prerequisites
check_ci_prerequisites() {
    print_status "Checking CI/CD prerequisites..."
    
    # Check kubectl availability in CI/CD environment
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not available in the CI/CD environment"
        exit 1
    fi
    
    # Check required environment variables
    local required_vars=("KUBE_CONFIG" "AZURE_SUBSCRIPTION_ID" "AZURE_TENANT_ID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            print_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    print_success "CI/CD prerequisites verified"
}

# Function to setup Kubernetes configuration in CI/CD
setup_k8s_config() {
    print_status "Setting up Kubernetes configuration for CI/CD..."
    
    # Setup kubeconfig from CI/CD environment
    if [[ -n "${KUBE_CONFIG:-}" ]]; then
        echo "$KUBE_CONFIG" | base64 -d > ~/.kube/config
        chmod 600 ~/.kube/config
    fi
    
    # Verify cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Unable to connect to Kubernetes cluster from CI/CD environment"
        exit 1
    fi
    
    print_success "Kubernetes configuration ready"
}

# Function to create namespace if it doesn't exist
create_namespace() {
    local namespace=$1
    
    if kubectl get namespace "$namespace" &> /dev/null; then
        print_status "Namespace $namespace already exists"
    else
        print_status "Creating namespace $namespace..."
        kubectl create namespace "$namespace"
        kubectl label namespace "$namespace" name="$namespace"
        print_success "Namespace $namespace created"
    fi
}

# Function to generate secrets from CI/CD environment
generate_secrets_from_environment() {
    print_status "Generating monitoring secrets from CI/CD environment..."
    
    # Generate Grafana secrets from environment or generate new ones
    GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 32)}"
    GRAFANA_SECRET_KEY="${GRAFANA_SECRET_KEY:-$(openssl rand -base64 32)}"
    
    # Create Grafana secrets
    kubectl create secret generic grafana-secrets \
        --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
        --from-literal=secret-key="$GRAFANA_SECRET_KEY" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Azure secrets from CI/CD environment variables
    kubectl create secret generic azure-secrets \
        --from-literal=client-id="${AZURE_CLIENT_ID}" \
        --from-literal=client-secret="${AZURE_CLIENT_SECRET}" \
        --from-literal=tenant-id="${AZURE_TENANT_ID}" \
        --from-literal=subscription-id="${AZURE_SUBSCRIPTION_ID}" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Monitoring secrets created from CI/CD environment"
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    print_status "Waiting for deployment $deployment in namespace $namespace to be ready..."
    
    if kubectl wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n $namespace; then
        print_success "Deployment $deployment is ready"
    else
        print_error "Deployment $deployment failed to become ready within ${timeout} seconds"
        kubectl describe deployment $deployment -n $namespace
        kubectl logs -l app=$deployment -n $namespace --tail=50
        return 1
    fi
}

# Function to apply Kubernetes manifests
apply_manifests() {
    local manifest_file=$1
    local description=$2
    
    print_status "Deploying $description..."
    
    if kubectl apply -f "$manifest_file"; then
        print_success "$description deployed successfully"
    else
        print_error "Failed to deploy $description"
        return 1
    fi
}

# Function to verify deployment in CI/CD
verify_deployment() {
    print_status "Verifying monitoring stack deployment..."
    
    # Check all deployments
    local deployments=("prometheus" "grafana" "loki" "tempo" "alertmanager")
    local failed_deployments=()
    
    for deployment in "${deployments[@]}"; do
        if kubectl get deployment "$deployment" -n "$NAMESPACE" &> /dev/null; then
            local replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
            local desired=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            
            if [[ "$replicas" == "$desired" ]] && [[ "$replicas" -gt 0 ]]; then
                print_success "$deployment: $replicas/$desired replicas ready"
            else
                print_warning "$deployment: $replicas/$desired replicas ready"
                failed_deployments+=("$deployment")
            fi
        else
            print_warning "$deployment: deployment not found"
            failed_deployments+=("$deployment")
        fi
    done
    
    # Check DaemonSet (Fluent Bit)
    if kubectl get daemonset fluent-bit -n "$NAMESPACE" &> /dev/null; then
        local ready=$(kubectl get daemonset fluent-bit -n "$NAMESPACE" -o jsonpath='{.status.numberReady}')
        local desired=$(kubectl get daemonset fluent-bit -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}')
        
        if [[ "$ready" == "$desired" ]] && [[ "$ready" -gt 0 ]]; then
            print_success "fluent-bit: $ready/$desired pods ready"
        else
            print_warning "fluent-bit: $ready/$desired pods ready"
            failed_deployments+=("fluent-bit")
        fi
    fi
    
    if [[ ${#failed_deployments[@]} -eq 0 ]]; then
        print_success "All monitoring components deployed successfully"
    else
        print_error "Some monitoring components failed to deploy: ${failed_deployments[*]}"
        return 1
    fi
}

# Function to run health checks
run_health_checks() {
    print_status "Running health checks..."
    
    # Check service endpoints
    local services=("prometheus" "grafana" "loki" "tempo" "alertmanager")
    
    for service in "${services[@]}"; do
        if kubectl get service "$service" -n "$NAMESPACE" &> /dev/null; then
            local cluster_ip=$(kubectl get service "$service" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
            print_success "Service $service available at $cluster_ip"
        else
            print_warning "Service $service not found"
        fi
    done
    
    # Run connectivity tests
    print_status "Running connectivity tests..."
    kubectl run --rm -i --tty --restart=Never test-pod --image=curlimages/curl --namespace="$NAMESPACE" -- \
        sh -c "curl -f http://prometheus:9090/-/healthy && echo 'Prometheus healthy'"
}

# Main deployment function for CI/CD
main() {
    print_status "Starting Healthcare Platform Observability Stack Deployment (CI/CD Mode)"
    
    # Verify CI/CD environment
    check_ci_environment
    
    # Check prerequisites
    check_ci_prerequisites
    
    # Setup Kubernetes configuration
    setup_k8s_config
    
    print_success "Connected to Kubernetes cluster from CI/CD environment"
    
    # Create namespaces
    create_namespace "$NAMESPACE"
    create_namespace "$HEALTHCARE_NAMESPACE"
    
    # Generate secrets from CI/CD environment
    generate_secrets_from_environment
    
    # Deploy monitoring stack components
    print_status "Deploying monitoring stack components..."
    
    # Deploy Prometheus stack
    apply_manifests "$MONITORING_DIR/prometheus-stack.yaml" "Prometheus monitoring stack"
    wait_for_deployment "$NAMESPACE" "prometheus" 300
    
    # Deploy Grafana stack
    apply_manifests "$MONITORING_DIR/grafana-stack.yaml" "Grafana visualization stack"
    wait_for_deployment "$NAMESPACE" "grafana" 300
    
    # Deploy Loki and Tempo stack
    apply_manifests "$MONITORING_DIR/loki-tempo-stack.yaml" "Loki and Tempo observability stack"
    wait_for_deployment "$NAMESPACE" "loki" 300
    wait_for_deployment "$NAMESPACE" "tempo" 300
    wait_for_deployment "$NAMESPACE" "alertmanager" 300
    
    # Verify deployment
    verify_deployment
    
    # Run health checks
    run_health_checks
    
    print_success "Healthcare Platform Observability Stack deployment completed successfully in CI/CD environment!"
    
    # Output important information for CI/CD logs
    print_status "=== Deployment Summary ==="
    print_status "Namespace: $NAMESPACE"
    print_status "Components deployed: Prometheus, Grafana, Loki, Tempo, AlertManager, Fluent Bit"
    print_status "Access: Configure ingress or load balancer for external access"
    print_status "Monitoring: Healthcare Platform comprehensive observability active"
}

# Parse command line arguments for CI/CD execution
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "verify")
        check_ci_environment
        check_ci_prerequisites
        setup_k8s_config
        verify_deployment
        ;;
    "health-check")
        check_ci_environment
        check_ci_prerequisites
        setup_k8s_config
        run_health_checks
        ;;
    *)
        echo "Usage: $0 {deploy|verify|health-check}"
        echo "  deploy      - Deploy the complete monitoring stack (CI/CD only)"
        echo "  verify      - Verify the deployment status (CI/CD only)"
        echo "  health-check - Run health checks (CI/CD only)"
        echo ""
        echo "IMPORTANT: This script must be executed in CI/CD pipelines only"
        echo "Supported CI/CD platforms:"
        echo "  - Azure DevOps Pipelines"
        echo "  - GitHub Actions"
        echo "  - Other enterprise CI/CD platforms"
        exit 1
        ;;
esac

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is required but not installed. Please install it first."
        exit 1
    fi
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    print_status "Waiting for deployment $deployment in namespace $namespace to be ready..."
    
    if kubectl wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n $namespace; then
        print_success "Deployment $deployment is ready"
    else
        print_error "Deployment $deployment failed to become ready within ${timeout} seconds"
        return 1
    fi
}

# Function to wait for pod to be ready
wait_for_pod() {
    local namespace=$1
    local label_selector=$2
    local timeout=${3:-300}
    
    print_status "Waiting for pods with selector '$label_selector' in namespace $namespace to be ready..."
    
    if kubectl wait --for=condition=ready --timeout=${timeout}s pod -l "$label_selector" -n $namespace; then
        print_success "Pods are ready"
    else
        print_error "Pods failed to become ready within ${timeout} seconds"
        return 1
    fi
}

# Function to create namespace if it doesn't exist
create_namespace() {
    local namespace=$1
    
    if kubectl get namespace "$namespace" &> /dev/null; then
        print_status "Namespace $namespace already exists"
    else
        print_status "Creating namespace $namespace..."
        kubectl create namespace "$namespace"
        kubectl label namespace "$namespace" name="$namespace"
        print_success "Namespace $namespace created"
    fi
}

# Function to generate secrets
generate_secrets() {
    print_status "Generating monitoring secrets..."
    
    # Generate Grafana admin password
    GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
    GRAFANA_SECRET_KEY=$(openssl rand -base64 32)
    
    # Create Grafana secrets
    kubectl create secret generic grafana-secrets \
        --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
        --from-literal=secret-key="$GRAFANA_SECRET_KEY" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Azure secrets (these should be populated from Key Vault or environment)
    kubectl create secret generic azure-secrets \
        --from-literal=client-id="${AZURE_CLIENT_ID:-placeholder}" \
        --from-literal=client-secret="${AZURE_CLIENT_SECRET:-placeholder}" \
        --from-literal=tenant-id="${AZURE_TENANT_ID:-placeholder}" \
        --from-literal=subscription-id="${AZURE_SUBSCRIPTION_ID:-placeholder}" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Monitoring secrets created"
    print_warning "Grafana admin password: $GRAFANA_ADMIN_PASSWORD"
    print_warning "Please update Azure secrets with actual values from Key Vault"
}

# Function to apply Kubernetes manifests
apply_manifests() {
    local manifest_file=$1
    local description=$2
    
    print_status "Deploying $description..."
    
    if kubectl apply -f "$manifest_file"; then
        print_success "$description deployed successfully"
    else
        print_error "Failed to deploy $description"
        return 1
    fi
}

# Function to create storage classes if needed
create_storage_classes() {
    print_status "Checking storage classes..."
    
    if ! kubectl get storageclass managed-premium &> /dev/null; then
        print_status "Creating managed-premium storage class..."
        cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-premium
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS
allowVolumeExpansion: true
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
EOF
        print_success "Storage class created"
    else
        print_status "Storage class managed-premium already exists"
    fi
}

# Function to port-forward services for access
setup_port_forwarding() {
    print_status "Setting up port forwarding for monitoring services..."
    
    # Kill any existing port-forward processes
    pkill -f "kubectl.*port-forward" || true
    
    # Port forward Grafana
    nohup kubectl port-forward -n "$NAMESPACE" svc/grafana 3000:3000 > /dev/null 2>&1 &
    GRAFANA_PID=$!
    
    # Port forward Prometheus
    nohup kubectl port-forward -n "$NAMESPACE" svc/prometheus 9090:9090 > /dev/null 2>&1 &
    PROMETHEUS_PID=$!
    
    # Port forward AlertManager
    nohup kubectl port-forward -n "$NAMESPACE" svc/alertmanager 9093:9093 > /dev/null 2>&1 &
    ALERTMANAGER_PID=$!
    
    print_success "Port forwarding setup complete:"
    print_success "  Grafana: http://localhost:3000"
    print_success "  Prometheus: http://localhost:9090"
    print_success "  AlertManager: http://localhost:9093"
    
    # Save PIDs for cleanup
    echo "$GRAFANA_PID $PROMETHEUS_PID $ALERTMANAGER_PID" > /tmp/monitoring_pids
}

# Function to verify deployment
verify_deployment() {
    print_status "Verifying monitoring stack deployment..."
    
    # Check all deployments
    local deployments=("prometheus" "grafana" "loki" "tempo" "alertmanager")
    
    for deployment in "${deployments[@]}"; do
        if kubectl get deployment "$deployment" -n "$NAMESPACE" &> /dev/null; then
            local replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
            local desired=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            
            if [[ "$replicas" == "$desired" ]] && [[ "$replicas" -gt 0 ]]; then
                print_success "$deployment: $replicas/$desired replicas ready"
            else
                print_warning "$deployment: $replicas/$desired replicas ready"
            fi
        else
            print_warning "$deployment: deployment not found"
        fi
    done
    
    # Check DaemonSet (Fluent Bit)
    if kubectl get daemonset fluent-bit -n "$NAMESPACE" &> /dev/null; then
        local ready=$(kubectl get daemonset fluent-bit -n "$NAMESPACE" -o jsonpath='{.status.numberReady}')
        local desired=$(kubectl get daemonset fluent-bit -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}')
        
        if [[ "$ready" == "$desired" ]] && [[ "$ready" -gt 0 ]]; then
            print_success "fluent-bit: $ready/$desired pods ready"
        else
            print_warning "fluent-bit: $ready/$desired pods ready"
        fi
    fi
    
    # Check PVCs
    print_status "Checking persistent volumes..."
    kubectl get pvc -n "$NAMESPACE"
    
    print_success "Monitoring stack verification complete"
}

# Function to display access information
display_access_info() {
    print_success "=== Healthcare Platform Monitoring Stack Deployed ==="
    echo
    print_status "Access URLs (via port-forward):"
    echo "  📊 Grafana Dashboard: http://localhost:3000"
    echo "     Username: admin"
    echo "     Password: (check secret or logs above)"
    echo
    echo "  📈 Prometheus: http://localhost:9090"
    echo "  🚨 AlertManager: http://localhost:9093"
    echo
    print_status "Default Dashboards Available:"
    echo "  • Healthcare Platform Overview"
    echo "  • HIPAA Compliance Monitoring"
    echo "  • Infrastructure Metrics"
    echo "  • Application Performance"
    echo "  • Security & Audit Logs"
    echo
    print_status "Monitoring Capabilities:"
    echo "  ✅ Metrics Collection (Prometheus)"
    echo "  ✅ Log Aggregation (Loki)"
    echo "  ✅ Distributed Tracing (Tempo)"
    echo "  ✅ Alerting (AlertManager)"
    echo "  ✅ Visualization (Grafana)"
    echo "  ✅ HIPAA Compliance Monitoring"
    echo "  ✅ Security Event Tracking"
    echo "  ✅ Performance Monitoring"
    echo
    print_warning "To stop port forwarding: kill \$(cat /tmp/monitoring_pids)"
}

# Function to cleanup on exit
cleanup() {
    if [[ -f /tmp/monitoring_pids ]]; then
        print_status "Cleaning up port-forward processes..."
        kill $(cat /tmp/monitoring_pids) 2>/dev/null || true
        rm -f /tmp/monitoring_pids
    fi
}

# Main deployment function
main() {
    print_status "Starting Healthcare Platform Observability Stack Deployment"
    
    # Check prerequisites
    print_status "Checking prerequisites..."
    check_command "kubectl"
    check_command "openssl"
    
    # Verify kubectl connection
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Unable to connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    print_success "Connected to Kubernetes cluster"
    
    # Create namespaces
    create_namespace "$NAMESPACE"
    create_namespace "$HEALTHCARE_NAMESPACE"
    
    # Create storage classes
    create_storage_classes
    
    # Generate secrets
    generate_secrets
    
    # Deploy monitoring stack components
    print_status "Deploying monitoring stack components..."
    
    # Deploy Prometheus stack
    apply_manifests "$MONITORING_DIR/prometheus-stack.yaml" "Prometheus monitoring stack"
    
    # Wait for Prometheus to be ready
    wait_for_deployment "$NAMESPACE" "prometheus" 300
    
    # Deploy Grafana stack
    apply_manifests "$MONITORING_DIR/grafana-stack.yaml" "Grafana visualization stack"
    
    # Wait for Grafana to be ready
    wait_for_deployment "$NAMESPACE" "grafana" 300
    
    # Deploy Loki and Tempo stack
    apply_manifests "$MONITORING_DIR/loki-tempo-stack.yaml" "Loki and Tempo observability stack"
    
    # Wait for core components
    wait_for_deployment "$NAMESPACE" "loki" 300
    wait_for_deployment "$NAMESPACE" "tempo" 300
    wait_for_deployment "$NAMESPACE" "alertmanager" 300
    
    # Wait for Fluent Bit DaemonSet
    wait_for_pod "$NAMESPACE" "app=fluent-bit" 180
    
    # Verify deployment
    verify_deployment
    
    # Setup port forwarding
    setup_port_forwarding
    
    # Display access information
    display_access_info
    
    print_success "Healthcare Platform Observability Stack deployment completed successfully!"
}

# Set up cleanup trap
trap cleanup EXIT

# Parse command line arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "verify")
        verify_deployment
        ;;
    "cleanup")
        print_status "Cleaning up monitoring stack..."
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
        print_success "Monitoring stack cleaned up"
        ;;
    "port-forward")
        setup_port_forwarding
        print_status "Port forwarding active. Press Ctrl+C to stop."
        wait
        ;;
    *)
        echo "Usage: $0 {deploy|verify|cleanup|port-forward}"
        echo "  deploy      - Deploy the complete monitoring stack"
        echo "  verify      - Verify the deployment status"
        echo "  cleanup     - Remove the monitoring stack"
        echo "  port-forward - Setup port forwarding only"
        exit 1
        ;;
esac
