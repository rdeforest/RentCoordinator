#!/bin/bash

# DR Test Stack Destruction
# Safely tears down the DR test stack after validation

set -e

STACK_NAME="rent-coordinator-dr-test"

echo "========================================"
echo "  DR Test Stack Destruction"
echo "========================================"
echo

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
    echo "✓ Stack $STACK_NAME does not exist (already deleted)"
    exit 0
fi

# Get stack status
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' \
    --output text)

echo "Stack status: $STACK_STATUS"
echo

# Confirm deletion
read -p "Are you sure you want to delete the DR test stack? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo
echo "Deleting stack $STACK_NAME..."

# Delete stack
aws cloudformation delete-stack --stack-name "$STACK_NAME"

echo "✓ Stack deletion initiated"
echo

# Wait for deletion
echo "Waiting for stack deletion to complete..."
echo "(This typically takes 3-5 minutes)"
echo

aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"

echo
echo "✅ Stack deleted successfully!"
echo
echo "DR test complete. Resources cleaned up."
echo
