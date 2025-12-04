#!/bin/bash
# Harbor IRSA Workshop - Infrastructure Deployment Script
# This script orchestrates the complete provisioning of the workshop infrastructure

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check for required tools
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install the missing tools:"
        echo "  - Terraform: https://www.terraform.io/downloads"
        echo "  - AWS CLI: https://aws.amazon.com/cli/"
        echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  - Helm: https://helm.sh/docs/intro/install/"
        exit 1
    fi
    
    print_success "All required tools are installed"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        echo ""
        echo "Please configure AWS credentials using one of:"
        echo "  - aws configure"
        echo "  - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
        echo "  - IAM role (if running on EC2)"
        exit 1
    fi
    
    print_success "AWS credentials are configured"
    
    # Display AWS account info
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local aws_region=$(aws configure get region || echo "us-east-1")
    print_info "AWS Account: $account_id"
    print_info "AWS Region: $aws_region"
}

validate_terraform_config() {
    print_header "Validating Terraform Configuration"
    
    cd "$TERRAFORM_DIR"
    
    # Check if terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        print_warning "terraform.tfvars not found"
        print_info "Creating terraform.tfvars from example..."
        cp terraform.tfvars.example terraform.tfvars
        print_warning "Please edit terraform.tfvars with your configuration"
        print_info "At minimum, change the harbor_admin_password"
        echo ""
        read -p "Press Enter to continue after editing terraform.tfvars..."
    fi
    
    print_success "Terraform configuration validated"
}

initialize_terraform() {
    print_header "Initializing Terraform"
    
    cd "$TERRAFORM_DIR"
    
    terraform init
    
    print_success "Terraform initialized"
}

plan_infrastructure() {
    print_header "Planning Infrastructure Changes"
    
    cd "$TERRAFORM_DIR"
    
    terraform plan -out=tfplan
    
    print_success "Terraform plan created"
    echo ""
    print_warning "Review the plan above carefully"
    read -p "Do you want to proceed with deployment? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Deployment cancelled"
        exit 0
    fi
}

deploy_infrastructure() {
    print_header "Deploying Infrastructure"
    
    cd "$TERRAFORM_DIR"
    
    print_info "This will take approximately 15-20 minutes..."
    print_info "Creating EKS cluster, VPC, S3 bucket, KMS key, and deploying Harbor..."
    
    terraform apply tfplan
    
    print_success "Infrastructure deployed successfully"
}

configure_kubectl() {
    print_header "Configuring kubectl"
    
    cd "$TERRAFORM_DIR"
    
    local cluster_name=$(terraform output -raw cluster_name)
    local aws_region=$(terraform output -raw aws_region 2>/dev/null || aws configure get region || echo "us-east-1")
    
    print_info "Updating kubeconfig for cluster: $cluster_name"
    aws eks update-kubeconfig --region "$aws_region" --name "$cluster_name"
    
    print_success "kubectl configured"
    
    # Verify connection
    print_info "Verifying cluster connection..."
    kubectl get nodes
    
    print_success "Successfully connected to cluster"
}

wait_for_harbor() {
    print_header "Waiting for Harbor to be Ready"
    
    local namespace=$(cd "$TERRAFORM_DIR" && terraform output -raw harbor_namespace)
    local max_wait=600  # 10 minutes
    local elapsed=0
    
    print_info "Waiting for Harbor pods to be ready (max ${max_wait}s)..."
    
    while [ $elapsed -lt $max_wait ]; do
        local ready_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        local total_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$total_pods" -gt 0 ] && [ "$ready_pods" -eq "$total_pods" ]; then
            print_success "All Harbor pods are ready ($ready_pods/$total_pods)"
            return 0
        fi
        
        echo -ne "\r${BLUE}Pods ready: $ready_pods/$total_pods (${elapsed}s elapsed)${NC}"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    echo ""
    print_warning "Timeout waiting for Harbor pods"
    print_info "You can check pod status with: kubectl get pods -n $namespace"
}

display_access_info() {
    print_header "Deployment Complete!"
    
    cd "$TERRAFORM_DIR"
    
    local namespace=$(terraform output -raw harbor_namespace)
    local release_name=$(terraform output -raw harbor_release_name 2>/dev/null || echo "harbor")
    
    echo ""
    print_success "Harbor IRSA Workshop infrastructure is ready!"
    echo ""
    
    print_info "Cluster Information:"
    terraform output cluster_name
    terraform output cluster_endpoint
    echo ""
    
    print_info "IRSA Configuration:"
    terraform output harbor_iam_role_arn
    terraform output service_account_annotation
    echo ""
    
    print_info "Storage Configuration:"
    terraform output s3_bucket_name
    terraform output kms_key_alias
    echo ""
    
    print_info "Getting Harbor access information..."
    
    # Wait a bit for LoadBalancer to be assigned
    sleep 10
    
    local harbor_url=$(kubectl get svc -n "$namespace" "${release_name}-portal" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    
    if [ "$harbor_url" != "pending" ] && [ -n "$harbor_url" ]; then
        echo ""
        print_success "Harbor URL: https://$harbor_url"
        print_info "Username: admin"
        print_info "Password: (run the command below to retrieve)"
        echo ""
        echo "  kubectl get secret -n $namespace ${release_name}-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 --decode && echo"
    else
        print_warning "LoadBalancer URL not yet available"
        print_info "Run this command to get the URL once ready:"
        echo ""
        echo "  kubectl get svc -n $namespace ${release_name}-portal -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
    fi
    
    echo ""
    print_info "Verification Commands:"
    echo "  # Check Harbor pods"
    echo "  kubectl get pods -n $namespace"
    echo ""
    echo "  # Check service account annotation"
    echo "  kubectl get sa -n $namespace harbor-registry -o yaml"
    echo ""
    echo "  # View Harbor logs"
    echo "  kubectl logs -n $namespace -l component=core"
    echo ""
    
    print_info "Next Steps:"
    echo "  1. Access Harbor UI using the URL above"
    echo "  2. Run validation tests in ../validation-tests/"
    echo "  3. Review CloudTrail logs for IRSA authentication"
    echo ""
}

# Main execution
main() {
    print_header "Harbor IRSA Workshop - Infrastructure Deployment"
    
    check_prerequisites
    validate_terraform_config
    initialize_terraform
    plan_infrastructure
    deploy_infrastructure
    configure_kubectl
    wait_for_harbor
    display_access_info
    
    print_success "Deployment script completed successfully!"
}

# Run main function
main "$@"
