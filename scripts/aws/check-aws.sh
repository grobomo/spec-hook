#!/usr/bin/env bash
# Check AWS connectivity
bash ~/.claude/skills/aws/aws.sh ec2 list 2>&1 | head -5
