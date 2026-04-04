#!/usr/bin/env bash
# Terminate the evidence test EC2 instance
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

INSTANCE_ID=$(cat "$PROJECT_DIR/instance-id.txt" 2>/dev/null)
if [ -z "$INSTANCE_ID" ]; then
  echo "No instance-id.txt found"
  exit 1
fi

echo "Terminating instance: $INSTANCE_ID"
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --output text
echo "Terminated."
