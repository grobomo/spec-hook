#!/usr/bin/env bash
# Start a stopped EC2 instance
# Usage: bash start-instance.sh INSTANCE_ID
set -euo pipefail
INSTANCE_ID="${1:?Usage: start-instance.sh INSTANCE_ID}"
bash ~/.claude/skills/aws/aws.sh ec2 start "$INSTANCE_ID"
