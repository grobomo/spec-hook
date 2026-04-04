#!/usr/bin/env bash
# List security groups
aws ec2 describe-security-groups --query 'SecurityGroups[*].[GroupId,GroupName,VpcId]' --output table
