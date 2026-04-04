#!/usr/bin/env bash
# Provision a fresh Ubuntu EC2 instance for SHTD evidence testing.
# Usage: bash scripts/aws/provision-evidence-instance.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Step 1: Check available key pairs ==="
aws ec2 describe-key-pairs --query 'KeyPairs[*].[KeyName]' --output text

echo ""
echo "=== Step 2: Find latest Ubuntu 22.04 AMI ==="
AMI=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)
echo "AMI: $AMI"

echo ""
echo "=== Step 3: Launch instance ==="
RESULT=$(aws ec2 run-instances \
  --image-id "$AMI" \
  --instance-type t3.large \
  --key-name ccc-worker-5-key \
  --security-group-ids sg-0e30f95f36812eb5f \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=shtd-evidence-test}]" \
  --count 1 \
  --output json)

INSTANCE_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Instances'][0]['InstanceId'])")
echo "Instance ID: $INSTANCE_ID"
echo "$INSTANCE_ID" > "$PROJECT_DIR/instance-id.txt"

echo ""
echo "=== Step 4: Wait for instance to be running ==="
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "Instance is running."

echo ""
echo "=== Step 5: Get public IP ==="
IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Public IP: $IP"
echo "$IP" > "$PROJECT_DIR/instance-ip.txt"

echo ""
echo "=== Step 6: Wait for SSH ==="
for i in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$HOME/.ssh/ccc-keys/worker-5.pem" ubuntu@"$IP" "echo ok" 2>/dev/null; then
    echo "SSH ready."
    break
  fi
  echo "  Waiting for SSH... ($i/30)"
  sleep 5
done

echo ""
echo "=== Done ==="
echo "Instance: $INSTANCE_ID"
echo "IP: $IP"
echo "SSH: ssh -i ~/.ssh/ccc-keys/worker-5.pem ubuntu@$IP"
