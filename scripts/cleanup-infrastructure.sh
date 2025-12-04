#!/bin/bash
# Harbor IRSA Workshop - Infrastructure Cleanup Script
# This script destroys all workshop infrastructure resources

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

confirm_destruction() {
    print_header "Confirm Infrastructure Destruction"
    
    print_warning "This will PERMANENTLY DELETE all workshop resources:"
    echo "  - EKS Cluster and all workloads"
    echo "  - VPC and networking resources"
    echo "  - S3 bucket and all stored images"
    echo "  - KMS encryption key"
    echo "  - IAM roles and policies"
    echo ""
    
    cd "$TERRAFORM_DIR"
    
    if [ -f "terraform.tfstate" ]; then
        print_info "Current infrastructure:"
        terraform show -no-color | head -20
        echo "..."
        echo ""
    fi
    
    print_warning "This action cannot be undone!"
    echo ""
    read -p "Type 'destroy' to confirm deletion: " confirm
    
    if [ "$confirm" != "destroy" ]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
    
    print_warning "Final confirmation required"
    read -p "Are you absolutely sure? (yes/no): " final_confirm
    
    if [ "$final_confirm" != "yes" ]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
}

empty_s3_bucket() {
    print_header "Emptying S3 Bucket"
    
    cd "$TERRAFORM_DIR"
    
    # Check if terraform state exists
    if [ ! -f "terraform.tfstate" ]; then
        print_warning "No terraform state found, skipping S3 cleanup"
        return 0
    fi
    
    # Get bucket name from terraform output
    local bucket_name=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    
    if [ -z "$bucket_name" ]; then
        print_warning "Could not determine S3 bucket name, skipping"
        return 0
    fi
    
    print_info "Emptying S3 bucket: $bucket_name"
    
    # Check if bucket exists
    if aws s3 ls "s3://$bucket_name" &> /dev/null; then
        print_info "Deleting all objects and versions..."
        
        # Delete all object versions
        aws s3api list-object-versions \
            --bucket "$bucket_name" \
            --output json \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            | jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' \
            | xargs -I {} aws s3api delete-object --bucket "$bucket_name" {} 2>/dev/null || true
        
        # Delete all delete markers
        aws s3api list-object-versions \
            --bucket "$bucket_name" \
            --output json \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            | jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' \
            | xargs -I {} aws s3api delete-object --bucket "$bucket_name" {} 2>/dev/null || true
        
        print_success "S3 bucket emptied"
    else
        print_info "S3 bucket does not exist or already deleted"
    fi
}

delete_load_balancers() {
    print_header "Cleaning up Load Balancers"
    
    cd "$TERRAFORM_DIR"
    
    local cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    
    if [ -z "$cluster_name" ]; then
        print_warning "Could not determine cluster name, skipping LB cleanup"
        return 0
    fi
    
    print_info "Looking for LoadBalancers created by Kubernetes..."
    
    # Get VPC ID
    local vpc_id=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    
    if [ -n "$vpc_id" ]; then
        # Find and delete load balancers in the VPC
        local lbs=$(aws elbv2 describe-load-balancers \
            --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$lbs" ]; then
            for lb in $lbs; do
                print_info "Deleting load balancer: $lb"
                aws elbv2 delete-load-balancer --load-balancer-arn "$lb" 2>/dev/null || true
            done
            
            print_info "Waiting for load balancers to be deleted..."
            sleep 30
            
            print_success "Load balancers cleaned up"
        else
            print_info "No load balancers found"
        fi
    fi
}

destroy_infrastructure() {
    print_header "Destroying Infrastructure"
    
    cd "$TERRAFORM_DIR"
    
    print_info "Running terraform destroy..."
    print_info "This will take approximately 10-15 minutes..."
    
    terraform destroy -auto-approve
    
    print_success "Infrastructure destroyed"
}

cleanup_local_files() {
    print_header "Cleaning up Local Files"
    
    cd "$TERRAFORM_DIR"
    
    print_info "Removing Terraform state and plan files..."
    
    rm -f terraform.tfstate
    rm -f terraform.tfstate.backup
    rm -f tfplan
    rm -f .terraform.lock.hcl
    rm -rf .terraform/
    
    print_success "Local files cleaned up"
}

remove_kubectl_context() {
    print_header "Removing kubectl Context"
    
    cd "$TERRAFORM_DIR"
    
    local cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    
    if [ -n "$cluster_name" ]; then
        local context_name=$(kubectl config get-contexts -o name | grep "$cluster_name" || echo "")
        
        if [ -n "$context_name" ]; then
            print_info "Removing kubectl context: $context_name"
            kubectl config delete-context "$context_name" 2>/dev/null || true
            print_success "kubectl context removed"
        fi
    fi
}

display_cleanup_summary() {
    print_header "Cleanup Complete"
    
    echo ""
    print_success "All workshop resources have been destroyed"
    echo ""
    
    print_info "Cleanup Summary:"
    echo "  ✓ EKS cluster deleted"
    echo "  ✓ VPC and networking resources deleted"
    echo "  ✓ S3 bucket emptied and deleted"
    echo "  ✓ KMS key scheduled for deletion"
    echo "  ✓ IAM roles and policies deleted"
    echo "  ✓ Local Terraform state cleaned up"
    echo ""
    
    print_info "Notes:"
    echo "  - KMS keys have a deletion window (default 30 days)"
    echo "  - CloudWatch logs may persist (check manually if needed)"
    echo "  - CloudTrail logs in your account are not affected"
    echo ""
    
    print_success "Workshop cleanup completed successfully!"
}

# Main execution
main() {
    print_header "Harbor IRSA Workshop - Infrastructure Cleanup"
    
    # Check if terraform directory exists
    if [ ! -d "$TERRAFORM_DIR" ]; then
        print_error "Terraform directory not found: $TERRAFORM_DIR"
        exit 1
    fi
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    confirm_destruction
    empty_s3_bucket
    delete_load_balancers
    destroy_infrastructure
    cleanup_local_files
    remove_kubectl_context
    display_cleanup_summary
}

# Run main function
main "$@"
