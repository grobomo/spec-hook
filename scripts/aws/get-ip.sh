#!/usr/bin/env bash
# Get public IP of an EC2 instance
# Usage: bash get-ip.sh INSTANCE_ID
set -euo pipefail
INSTANCE_ID="${1:?Usage: get-ip.sh INSTANCE_ID}"
bash ~/.claude/skills/aws/aws.sh ec2 list 2>&1 | grep "$INSTANCE_ID" | awk '{print $4}'
