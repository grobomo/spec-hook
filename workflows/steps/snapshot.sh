#!/usr/bin/env bash
# Workflow step: snapshot — Create AMI golden image from tested instance
#
# Requires: .test-results/remote-install.passed
# Produces: ami-id.txt

set -euo pipefail

PROJECT_DIR="${1:-.}"
INSTANCE_ID=$(cat "${PROJECT_DIR}/instance-id.txt")
NAME=$(cat "${PROJECT_DIR}/instance-name.txt" 2>/dev/null || echo "shtd-test")
AMI_NAME="shtd-golden-${NAME}-$(date +%Y%m%d-%H%M)"

echo "Creating AMI from ${INSTANCE_ID}..."

# If container mode, commit Docker state first
MODE="${INSTALL_MODE:-container}"
IP=$(cat "${PROJECT_DIR}/instance-ip.txt")
SSH_KEY="${HOME}/.ssh/claude-portable.pem"

if [ "$MODE" = "container" ]; then
  echo "Committing Docker container state..."
  ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$IP" \
    "docker commit claude-portable claude-shtd-golden:latest" 2>/dev/null || true
fi

# Create AMI
AMI_ID=$(aws ec2 create-image \
  --instance-id "$INSTANCE_ID" \
  --name "$AMI_NAME" \
  --description "CCC worker with Claude Code + SHTD flow pre-installed" \
  --no-reboot \
  --query 'ImageId' --output text)

if [ -z "$AMI_ID" ]; then
  echo "ERROR: Failed to create AMI"
  exit 1
fi

echo "$AMI_ID" > "${PROJECT_DIR}/ami-id.txt"
echo "$AMI_NAME" > "${PROJECT_DIR}/ami-name.txt"

# Tag the AMI
aws ec2 create-tags --resources "$AMI_ID" --tags \
  Key=Name,Value="$AMI_NAME" \
  Key=Project,Value=spec-hook \
  Key=Type,Value=ccc-golden-image

# Wait for AMI to be available
echo "Waiting for AMI ${AMI_ID} to become available..."
for i in $(seq 1 60); do
  STATE=$(aws ec2 describe-images --image-ids "$AMI_ID" --query "Images[0].State" --output text 2>/dev/null || echo "unknown")
  if [ "$STATE" = "available" ]; then
    echo "AMI ready: ${AMI_ID} (${AMI_NAME})"
    exit 0
  fi
  sleep 15
done

echo "WARNING: AMI still pending after 15 min. ID saved: ${AMI_ID}"
