#!/usr/bin/env bash
# Workflow step: cleanup — Terminate EC2 instance after AMI capture
#
# Requires: ami-id.txt
# Produces: cleanup-done.txt

set -euo pipefail

PROJECT_DIR="${1:-.}"
NAME=$(cat "${PROJECT_DIR}/instance-name.txt" 2>/dev/null || echo "shtd-test")
INSTANCE_ID=$(cat "${PROJECT_DIR}/instance-id.txt")
STACK_NAME="claude-portable-${NAME}"
CLAUDE_PORTABLE="${HOME}/Documents/ProjectsCL1/claude-portable"

echo "Cleaning up instance ${INSTANCE_ID}..."

# Prefer CF stack deletion (handles SG, key pair cleanup)
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
  echo "Deleting CF stack: ${STACK_NAME}..."
  if [ -f "${CLAUDE_PORTABLE}/terminate.sh" ]; then
    cd "$CLAUDE_PORTABLE" && bash terminate.sh --name "$NAME" 2>&1
  else
    aws cloudformation delete-stack --stack-name "$STACK_NAME"
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null || true
  fi
else
  # Direct termination fallback
  echo "Terminating instance directly..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null
fi

echo "cleanup-done $(date -Iseconds)" > "${PROJECT_DIR}/cleanup-done.txt"

AMI_ID=$(cat "${PROJECT_DIR}/ami-id.txt" 2>/dev/null || echo "none")
echo ""
echo "Cleanup complete."
echo "AMI preserved: ${AMI_ID}"
echo "Use this AMI for new CCC workers with SHTD pre-installed."
