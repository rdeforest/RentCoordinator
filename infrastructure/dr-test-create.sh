#!/bin/bash

# DR Test Stack Creation
# Creates a parallel CloudFormation stack to validate disaster recovery procedures
# Should be run quarterly or after major infrastructure changes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="rent-coordinator-dr-test"
TEMPLATE_FILE="$SCRIPT_DIR/cloudformation/rent-coordinator-infrastructure.yaml"
PARAMETERS_FILE="$SCRIPT_DIR/cloudformation/parameters-dr-test.json"

echo "========================================"
echo "  DR Test Stack Creation"
echo "========================================"
echo
echo "This will create a temporary test stack to validate DR procedures."
echo "Stack name: $STACK_NAME"
echo "Template: $TEMPLATE_FILE"
echo "Parameters: $PARAMETERS_FILE"
echo
echo "Note: This will briefly add an instance to the production target group."
echo "      The test instance will be torn down shortly after validation."
echo

# Check if stack already exists
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
    echo "❌ Stack $STACK_NAME already exists!"
    echo "   Run ./dr-test-destroy.sh first to clean up."
    exit 1
fi

echo "✓ Stack does not exist, proceeding with creation..."
echo

# Validate template
echo "Validating CloudFormation template..."
aws cloudformation validate-template \
    --template-body "file://$TEMPLATE_FILE" > /dev/null
echo "✓ Template is valid"
echo

# Create stack
echo "Creating stack $STACK_NAME..."
aws cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body "file://$TEMPLATE_FILE" \
    --parameters "file://$PARAMETERS_FILE" \
    --capabilities CAPABILITY_NAMED_IAM \
    --tags \
        Key=Purpose,Value=DR-Test \
        Key=AutoDelete,Value=true \
        Key=CreatedBy,Value="$(whoami)" \
        Key=CreatedAt,Value="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "✓ Stack creation initiated"
echo

# Wait for creation
echo "Waiting for stack creation to complete..."
echo "(This typically takes 8-15 minutes)"
echo

aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"

echo
echo "✅ Stack created successfully!"
echo
echo "Next steps:"
echo "  1. Run ./dr-test-verify.sh to validate the stack"
echo "  2. Run ./dr-test-destroy.sh to clean up when done"
echo

# Show stack outputs
echo "Stack Information:"
aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].[StackName,StackStatus,CreationTime]' \
    --output table
