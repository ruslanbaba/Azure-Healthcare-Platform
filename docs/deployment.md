# Azure Healthcare Analytics Platform - Deployment Guide

## Prerequisites

Before deploying the Azure Healthcare Analytics Platform, ensure you have the following prerequisites in place:

### Required Tools
- **Azure CLI** (version 2.50.0 or later)
- **Terraform** (version 1.6.0 or later)
- **kubectl** (version 1.28.0 or later)
- **Helm** (version 3.12.0 or later)
- **Docker** (version 24.0.0 or later)
- **Git** (version 2.40.0 or later)

### Azure Subscriptions and Permissions
- Azure subscription with Owner or Contributor permissions
- Azure Active Directory Global Administrator (for initial setup)
- Service Principal with appropriate permissions for CI/CD

### Network Requirements
- Dedicated virtual network CIDR block (recommended: /16)
- DNS zone management (if using custom domains)
- Firewall rules configured for outbound internet access

## Installation Steps

### Step 1: Initial Azure Setup

#### 1.1 Create Service Principal for Terraform
```bash
# Login to Azure CLI
az login

# Set the subscription
az account set --subscription "your-subscription-id"

# Create service principal
az ad sp create-for-rbac --name "terraform-healthcare-platform" \
    --role="Contributor" \
    --scopes="/subscriptions/your-subscription-id"

# Note down the output:
# {
#   "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "displayName": "terraform-healthcare-platform",
#   "password": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# }
```

#### 1.2 Create Storage Account for Terraform State
```bash
# Create resource group for Terraform state
az group create --name "tf-state-rg" --location "East US 2"

# Create storage account
az storage account create \
    --name "tfstatehealth$(date +%s)" \
    --resource-group "tf-state-rg" \
    --location "East US 2" \
    --sku "Standard_LRS" \
    --encryption-services "blob"

# Create container
az storage container create \
    --name "tfstate" \
    --account-name "tfstatehealth$(date +%s)"
```

#### 1.3 Set Environment Variables
```bash
export ARM_CLIENT_ID="your-service-principal-app-id"
export ARM_CLIENT_SECRET="your-service-principal-password"
export ARM_SUBSCRIPTION_ID="your-subscription-id"
export ARM_TENANT_ID="your-tenant-id"
```

### Step 2: Clone and Configure Repository

#### 2.1 Clone Repository
```bash
git clone https://github.com/ruslanbaba/Azure-Healthcare-Platform.git
cd Azure-Healthcare-Platform
```

#### 2.2 Configure Backend Configuration
Create `infrastructure/terraform/backend.conf`:
```hcl
resource_group_name  = "tf-state-rg"
storage_account_name = "your-terraform-storage-account"
container_name       = "tfstate"
key                 = "prod.terraform.tfstate"
```

#### 2.3 Customize Environment Variables
Edit `infrastructure/terraform/environments/prod.tfvars`:
```hcl
# Update these values for your environment
project_name = "healthcare-analytics"
location     = "East US 2"
owner        = "Your Healthcare Team"
cost_center  = "Your Cost Center"

# Network Configuration
vnet_address_space = ["10.0.0.0/16"]

# Update admin email for alerts
apim_config = {
  sku_name          = "Premium"
  publisher_name    = "Your Organization"
  publisher_email   = "your-admin@yourorg.com"
}
```

### Step 3: Infrastructure Deployment

#### 3.1 Initialize Terraform
```bash
cd infrastructure/terraform

# Initialize Terraform with backend configuration
terraform init -backend-config=backend.conf

# Validate configuration
terraform validate
```

#### 3.2 Plan Deployment
```bash
# Generate deployment plan
terraform plan -var-file="environments/prod.tfvars" -out=prod.tfplan

# Review the plan carefully before proceeding
```

#### 3.3 Deploy Infrastructure
```bash
# Apply the Terraform plan
terraform apply prod.tfplan

# This will take approximately 30-45 minutes to complete
```

#### 3.4 Capture Outputs
```bash
# Save important outputs
terraform output -json > ../outputs.json

# Extract key information
export AKS_RESOURCE_GROUP=$(terraform output -raw resource_groups | jq -r '.compute')
export AKS_CLUSTER_NAME=$(terraform output -raw aks | jq -r '.cluster_name')
export ACR_NAME=$(terraform output -raw container_registry | jq -r '.name')
export KEY_VAULT_NAME=$(terraform output -raw security | jq -r '.key_vault_name')
```

### Step 4: Configure Kubernetes Access

#### 4.1 Get AKS Credentials
```bash
# Get AKS credentials
az aks get-credentials \
    --resource-group $AKS_RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --overwrite-existing

# Verify connectivity
kubectl get nodes
```

#### 4.2 Install Required Kubernetes Components

##### Install NGINX Ingress Controller
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

##### Install Cert-Manager
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.13.3 \
    --set installCRDs=true
```

##### Install Prometheus and Grafana
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set grafana.adminPassword="your-secure-password"
```

### Step 5: Application Deployment

#### 5.1 Configure Container Registry Access
```bash
# Login to Azure Container Registry
az acr login --name $ACR_NAME

# Create Kubernetes secret for ACR access
kubectl create secret docker-registry acr-secret \
    --docker-server=$ACR_NAME.azurecr.io \
    --docker-username=$(az acr credential show --name $ACR_NAME --query username -o tsv) \
    --docker-password=$(az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv) \
    --namespace healthcare-platform
```

#### 5.2 Build and Push Application Images
```bash
# Build data processor image
cd applications/data-processor
docker build -t $ACR_NAME.azurecr.io/data-processor:v1.0.0 .
docker push $ACR_NAME.azurecr.io/data-processor:v1.0.0

# Tag as latest
docker tag $ACR_NAME.azurecr.io/data-processor:v1.0.0 $ACR_NAME.azurecr.io/data-processor:latest
docker push $ACR_NAME.azurecr.io/data-processor:latest

cd ../..
```

#### 5.3 Configure Application Values
Edit `charts/healthcare-platform/values-prod.yaml`:
```yaml
# Update these values based on your Terraform outputs
image:
  registry: your-acr-name.azurecr.io
  tag: "v1.0.0"

env:
  STORAGE_ACCOUNT_NAME: "your-storage-account-name"
  KEY_VAULT_URL: "https://your-key-vault-name.vault.azure.net/"

workloadIdentity:
  enabled: true
  clientId: "your-workload-identity-client-id"

secrets:
  keyVaultName: "your-key-vault-name"

ingress:
  hosts:
    - host: api.your-domain.com
      paths:
        - path: /
          pathType: Prefix
          service: api-gateway
```

#### 5.4 Deploy Application
```bash
# Install the healthcare platform
helm install healthcare-platform ./charts/healthcare-platform \
    --namespace healthcare-platform \
    --create-namespace \
    --values ./charts/healthcare-platform/values-prod.yaml \
    --wait

# Verify deployment
kubectl get pods -n healthcare-platform
kubectl get services -n healthcare-platform
kubectl get ingress -n healthcare-platform
```

### Step 6: Configure DNS and SSL

#### 6.1 Get Load Balancer IP
```bash
# Get the external IP of the ingress controller
kubectl get service ingress-nginx-controller \
    --namespace ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

#### 6.2 Configure DNS Records
Create A records in your DNS provider:
- `api.your-domain.com` → Load Balancer IP
- `analytics.your-domain.com` → Load Balancer IP

#### 6.3 Configure SSL Certificates
```bash
# Create ClusterIssuer for Let's Encrypt
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-admin@yourorg.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### Step 7: Verify Deployment

#### 7.1 Health Checks
```bash
# Check pod status
kubectl get pods -n healthcare-platform

# Check service endpoints
kubectl get endpoints -n healthcare-platform

# Check ingress status
kubectl describe ingress healthcare-platform-ingress -n healthcare-platform
```

#### 7.2 Application Tests
```bash
# Test API endpoint
curl -k https://api.your-domain.com/health

# Test analytics endpoint
curl -k https://analytics.your-domain.com/health

# Check SSL certificate
curl -vI https://api.your-domain.com 2>&1 | grep -A 10 "SSL certificate"
```

#### 7.3 Monitoring Verification
```bash
# Access Grafana dashboard
kubectl port-forward service/prometheus-grafana 3000:80 -n monitoring

# Open browser to http://localhost:3000
# Default credentials: admin / your-secure-password

# Check Prometheus targets
kubectl port-forward service/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
# Open browser to http://localhost:9090/targets
```

## Post-Deployment Configuration

### Security Hardening

#### 1. Update Default Passwords
```bash
# Update Grafana admin password
kubectl patch secret prometheus-grafana \
    -n monitoring \
    --type='json' \
    -p='[{"op": "replace", "path": "/data/admin-password", "value":"'$(echo -n "new-secure-password" | base64)'"}]'
```

#### 2. Configure Network Policies
```bash
# Apply network policies for microsegmentation
kubectl apply -f monitoring/network-policies/
```

#### 3. Enable Pod Security Standards
```bash
# Label namespaces with security standards
kubectl label namespace healthcare-platform \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/warn=restricted
```

### Monitoring Configuration

#### 1. Configure Alerts
```bash
# Apply custom alert rules
kubectl apply -f monitoring/alerts/healthcare-alerts.yaml
```

#### 2. Set up Log Aggregation
```bash
# Configure Fluent Bit for log collection
helm install fluent-bit fluent/fluent-bit \
    --namespace monitoring \
    --set backend.type=azureloganalytics \
    --set backend.azureLogAnalytics.workspaceId=$WORKSPACE_ID \
    --set backend.azureLogAnalytics.sharedKey=$WORKSPACE_KEY
```

### Backup Configuration

#### 1. Configure Velero for Kubernetes Backups
```bash
# Install Velero for cluster backups
velero install \
    --provider azure \
    --plugins velero/velero-plugin-for-microsoft-azure:v1.8.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --backup-location-config resourceGroup=$AZURE_BACKUP_RESOURCE_GROUP,storageAccount=$AZURE_STORAGE_ACCOUNT_ID
```

#### 2. Schedule Regular Backups
```bash
# Create daily backup schedule
velero create schedule healthcare-platform-daily \
    --schedule="0 2 * * *" \
    --include-namespaces healthcare-platform \
    --ttl 720h0m0s
```

## Maintenance and Updates

### Regular Maintenance Tasks

#### 1. Update Kubernetes Cluster
```bash
# Check available upgrades
az aks get-upgrades --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME

# Upgrade cluster (during maintenance window)
az aks upgrade --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --kubernetes-version "1.28.x"
```

#### 2. Update Application Images
```bash
# Update application with new image version
helm upgrade healthcare-platform ./charts/healthcare-platform \
    --namespace healthcare-platform \
    --set image.tag="v1.1.0" \
    --reuse-values
```

#### 3. Certificate Renewal
```bash
# Check certificate expiration
kubectl describe certificate healthcare-platform-tls -n healthcare-platform

# Force certificate renewal if needed
kubectl delete secret healthcare-platform-tls -n healthcare-platform
```

### Troubleshooting

#### Common Issues and Solutions

1. **Pod Startup Issues**
   ```bash
   # Check pod logs
   kubectl logs -f deployment/healthcare-platform-data-processor -n healthcare-platform
   
   # Check events
   kubectl get events -n healthcare-platform --sort-by='.lastTimestamp'
   ```

2. **Ingress Issues**
   ```bash
   # Check ingress controller logs
   kubectl logs -f deployment/ingress-nginx-controller -n ingress-nginx
   
   # Verify ingress configuration
   kubectl describe ingress healthcare-platform-ingress -n healthcare-platform
   ```

3. **Certificate Issues**
   ```bash
   # Check cert-manager logs
   kubectl logs -f deployment/cert-manager -n cert-manager
   
   # Check certificate requests
   kubectl get certificaterequests -n healthcare-platform
   ```

This deployment guide provides a comprehensive walkthrough for setting up the Azure Healthcare Analytics Platform. Follow each step carefully and ensure all prerequisites are met before proceeding to the next step.
