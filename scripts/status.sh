#!/usr/bin/env bash
# What is running (and billing) right now? Read-only.
source "$(dirname "$0")/lib.sh"
require_tools aws
export AWS_PAGER=""

none_if_empty() { [[ -n "${1// /}" ]] && echo "$1" || echo "none"; }

EKS="$(aws eks list-clusters --region $REGION --query 'clusters' --output text)"
EC2="$(aws ec2 describe-instances --region $REGION --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceType' --output text)"
LBS="$(aws elbv2 describe-load-balancers --region $REGION --query 'LoadBalancers[].LoadBalancerName' --output text)"
# Volumes tagged Backup are deliberate (GitLab data volume); the rest are strays
FREE_ALL="$(aws ec2 describe-volumes --region $REGION --filters Name=status,Values=available --query 'length(Volumes)' --output text)"
FREE_KEPT="$(aws ec2 describe-volumes --region $REGION --filters Name=status,Values=available Name=tag-key,Values=Backup --query 'length(Volumes)' --output text)"

echo "EKS cluster (\$0.10/h):  $(none_if_empty "$EKS")"
echo "EC2 running:            $(none_if_empty "$EC2")"
echo "NAT gateways (\$1/day):  $(aws ec2 describe-nat-gateways --region $REGION --filter Name=state,Values=available --query 'length(NatGateways)' --output text)"
echo "Load balancers:         $(none_if_empty "$LBS")"
echo "Unattached EBS volumes: $((FREE_ALL - FREE_KEPT)) stray, $FREE_KEPT kept on purpose (GitLab data)"
IPS="$(aws ec2 describe-addresses --region $REGION --query 'length(Addresses)' --output text)"
echo "Public IPv4 addresses:  $IPS (each bills about \$0.12/day; the NAT and every ALB have them)"

# One line that answers "am I paying for anything big right now?"
NATS="$(aws ec2 describe-nat-gateways --region $REGION --filter Name=state,Values=available --query 'length(NatGateways)' --output text)"
if [[ -z "${EKS// /}" && -z "${EC2// /}" && -z "${LBS// /}" && "$NATS" == 0 ]]; then
  echo "Verdict: everything expensive is off. Only disks, snapshots and the DNS zone bill now (about \$0.2 a day)."
else
  echo "Verdict: something is still running. See the lines above."
fi
