#!/bin/bash
# RentCoordinator Infrastructure Deployment Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="${STACK_NAME:-rent-coordinator-production}"
REGION="${AWS_REGION:-us-west-2}"
TEMPLATE_FILE="$SCRIPT_DIR/cloudformation/rent-coordinator-infrastructure.yaml"
PARAMETERS_FILE="$SCRIPT_DIR/cloudformation/parameters.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
  cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Deploy and manage RentCoordinator AWS infrastructure

COMMANDS:
  deploy      Deploy or update infrastructure stack
  delete      Delete infrastructure stack
  status      Show stack status and outputs
  instances   List instances in Auto Scaling Group
  scale       Scale Auto Scaling Group
  refresh     Perform instance refresh (rolling update)
  validate    Validate CloudFormation template

OPTIONS:
  --stack-name NAME    Stack name (default: $STACK_NAME)
  --region REGION      AWS region (default: $REGION)
  --parameters FILE    Parameters file (default: $PARAMETERS_FILE)
  --help              Show this help message

EXAMPLES:
  # Deploy infrastructure
  $0 deploy

  # Deploy with custom stack name
  $0 deploy --stack-name rent-coordinator-staging

  # Check status
  $0 status

  # Scale to 2 instances
  $0 scale 2

  # Perform rolling update
  $0 refresh

  # Delete stack
  $0 delete

ENVIRONMENT VARIABLES:
  STACK_NAME           Override default stack name
  AWS_REGION           Override default AWS region

EOF
  exit 0
}

validate_prerequisites() {
  print_info "Validating prerequisites..."

  # Check AWS CLI
  if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install it first."
    exit 1
  fi

  # Check AWS credentials
  if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured or invalid."
    exit 1
  fi

  # Check parameters file
  if [ ! -f "$PARAMETERS_FILE" ]; then
    print_error "Parameters file not found: $PARAMETERS_FILE"
    print_info "Copy parameters-example.json to parameters.json and edit with your values"
    exit 1
  fi

  print_success "Prerequisites validated"
}

validate_template() {
  print_info "Validating CloudFormation template..."

  if aws cloudformation validate-template \
    --template-body "file://$TEMPLATE_FILE" \
    --region "$REGION" &> /dev/null; then
    print_success "Template is valid"
  else
    print_error "Template validation failed"
    exit 1
  fi
}

deploy_stack() {
  validate_prerequisites
  validate_template

  print_info "Deploying stack: $STACK_NAME"

  # Check if stack exists
  if aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" &> /dev/null; then

    print_info "Stack exists, performing update..."
    aws cloudformation update-stack \
      --stack-name "$STACK_NAME" \
      --template-body "file://$TEMPLATE_FILE" \
      --parameters "file://$PARAMETERS_FILE" \
      --capabilities CAPABILITY_NAMED_IAM \
      --region "$REGION"

    print_info "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete \
      --stack-name "$STACK_NAME" \
      --region "$REGION"

    print_success "Stack updated successfully"
  else
    print_info "Creating new stack..."
    aws cloudformation create-stack \
      --stack-name "$STACK_NAME" \
      --template-body "file://$TEMPLATE_FILE" \
      --parameters "file://$PARAMETERS_FILE" \
      --capabilities CAPABILITY_NAMED_IAM \
      --region "$REGION"

    print_info "Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete \
      --stack-name "$STACK_NAME" \
      --region "$REGION"

    print_success "Stack created successfully"
  fi

  show_status
}

delete_stack() {
  print_warning "This will delete all infrastructure created by CloudFormation"
  read -p "Are you sure? (yes/no): " -r
  if [[ ! $REPLY =~ ^yes$ ]]; then
    print_info "Aborted"
    exit 0
  fi

  print_info "Deleting stack: $STACK_NAME"
  aws cloudformation delete-stack \
    --stack-name "$STACK_NAME" \
    --region "$REGION"

  print_info "Waiting for stack deletion to complete..."
  aws cloudformation wait stack-delete-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION"

  print_success "Stack deleted successfully"
}

show_status() {
  print_info "Stack status for: $STACK_NAME"

  STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [ "$STATUS" = "NOT_FOUND" ]; then
    print_error "Stack not found"
    exit 1
  fi

  echo ""
  echo "Status: $STATUS"
  echo ""

  print_info "Stack outputs:"
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

  # Get ASG name and show instances
  ASG_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
    --output text)

  if [ -n "$ASG_NAME" ]; then
    echo ""
    print_info "Auto Scaling Group: $ASG_NAME"
    list_instances "$ASG_NAME"
  fi
}

list_instances() {
  local asg_name="${1:-$(get_asg_name)}"

  print_info "Instances in Auto Scaling Group: $asg_name"
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$asg_name" \
    --region "$REGION" \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState,AvailabilityZone]' \
    --output table
}

get_asg_name() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
    --output text
}

scale_asg() {
  local desired_capacity="$1"

  if [ -z "$desired_capacity" ]; then
    print_error "Please specify desired capacity: $0 scale <number>"
    exit 1
  fi

  local asg_name
  asg_name=$(get_asg_name)

  print_info "Scaling Auto Scaling Group to $desired_capacity instances..."
  aws autoscaling set-desired-capacity \
    --auto-scaling-group-name "$asg_name" \
    --desired-capacity "$desired_capacity" \
    --region "$REGION"

  print_success "Desired capacity set to $desired_capacity"
  print_info "Instances will launch/terminate to match desired capacity"
}

refresh_instances() {
  local asg_name
  asg_name=$(get_asg_name)

  print_info "Starting instance refresh for: $asg_name"
  print_info "This will perform a rolling update of all instances"

  aws autoscaling start-instance-refresh \
    --auto-scaling-group-name "$asg_name" \
    --preferences MinHealthyPercentage=50 \
    --region "$REGION"

  print_success "Instance refresh started"
  print_info "Monitor progress with: $0 status"
}

# Parse arguments
COMMAND="${1:-}"
shift || true

while [[ $# -gt 0 ]]; do
  case $1 in
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --parameters)
      PARAMETERS_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      break
      ;;
  esac
done

# Execute command
case "$COMMAND" in
  deploy)
    deploy_stack
    ;;
  delete)
    delete_stack
    ;;
  status)
    show_status
    ;;
  instances)
    list_instances
    ;;
  scale)
    scale_asg "$1"
    ;;
  refresh)
    refresh_instances
    ;;
  validate)
    validate_template
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    print_error "Unknown command: $COMMAND"
    echo ""
    usage
    ;;
esac
