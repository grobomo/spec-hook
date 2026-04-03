#!/usr/bin/env bash
# Workflow step: provision — Launch EC2 instance for Claude Code testing
# Works in both container and native environments.
#
# Requires: AWS CLI configured, SSH key pair, cloud-claude skill
# Produces: instance-id.txt, instance-ip.txt

set -euo pipefail

PROJECT_DIR="${1:-.}"
INSTANCE_NAME="shtd-test-$(date +%s | tail -c 6)"
CLAUDE_PORTABLE="${HOME}/Documents/ProjectsCL1/claude-portable"

# Verify AWS access
echo "Checking AWS credentials..."
aws sts get-caller-identity --query Account --output text > /dev/null 2>&1 || {
  echo "ERROR: AWS CLI not configured. Run: aws configure"
  exit 1
}

# Verify claude-portable exists
if [ ! -d "$CLAUDE_PORTABLE" ]; then
  echo "Cloning claude-portable..."
  git clone https://github.com/grobomo/claude-portable.git "$CLAUDE_PORTABLE"
fi

# Get API key from credential manager
CRED_CLI="${HOME}/.claude/skills/credential-manager/cred_cli.py"
API_KEY=""
if [ -f "$CRED_CLI" ]; then
  API_KEY=$(python "$CRED_CLI" get hackathon ANTHROPIC_API_KEY 2>/dev/null || echo "")
fi

if [ -z "$API_KEY" ]; then
  # Fallback: check env var
  API_KEY="${ANTHROPIC_API_KEY:-}"
fi

if [ -z "$API_KEY" ]; then
  echo "ERROR: No ANTHROPIC_API_KEY found. Store with: python cred_cli.py store hackathon ANTHROPIC_API_KEY"
  exit 1
fi

# Write .env for claude-portable
cat > "$CLAUDE_PORTABLE/.env" << EOF
ANTHROPIC_API_KEY=${API_KEY}
REPO_URL=https://github.com/grobomo/spec-hook.git
EOF

# Launch instance
echo "Launching EC2 instance: ${INSTANCE_NAME}..."
cd "$CLAUDE_PORTABLE"
bash run.sh --name "$INSTANCE_NAME" 2>&1

# Extract instance ID and IP from CF stack
STACK_NAME="claude-portable-${INSTANCE_NAME}"
INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text 2>/dev/null || echo "")
INSTANCE_IP=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='PublicIP'].OutputValue" --output text 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ] || [ -z "$INSTANCE_IP" ]; then
  echo "ERROR: Could not get instance ID/IP from stack ${STACK_NAME}"
  exit 1
fi

# Write outputs
echo "$INSTANCE_ID" > "${PROJECT_DIR}/instance-id.txt"
echo "$INSTANCE_IP" > "${PROJECT_DIR}/instance-ip.txt"
echo "$INSTANCE_NAME" > "${PROJECT_DIR}/instance-name.txt"

echo "Instance provisioned: ${INSTANCE_ID} at ${INSTANCE_IP}"
echo "Stack: ${STACK_NAME}"
