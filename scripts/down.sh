#!/usr/bin/env bash
# END OF WORK DAY: switch off everything that bills by the hour, keep everything that holds data.
# Usage: down.sh              -> everything expensive off (about $0.2/day remains)
#        down.sh --keep-edge  -> destroy EKS and GitLab only, keep NAT, ALB and Jenkins (about $2.8/day)
#        down.sh --deep       -> same as the default
source "$(dirname "$0")/lib.sh"
require_tools aws kubectl terraform terragrunt

# If anything fails halfway, say so: resources may still be billing
trap 'echo; warn "down.sh stopped before it finished, so things may still be billing. Read the error above, fix it and run down.sh again (it is safe to repeat), then check scripts/status.sh."' ERR

KEEP_EDGE=0
for arg in "$@"; do
  case "$arg" in
    --keep-edge) KEEP_EDGE=1 ;;
    --deep) ;;
    *) echo "Unknown option: $arg (supported: --keep-edge, --deep)"; exit 1 ;;
  esac
done

if cluster_exists; then
  say "1/3 Removing things Kubernetes created OUTSIDE Terraform (load balancers, DNS)"
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
  # Stop Argo CD first or selfHeal recreates the Gateway and the routes (keep the apps, the controllers delete the ALB)
  kubectl -n argocd scale statefulset argocd-application-controller --replicas=0 2>&1 || true
  kubectl -n argocd scale deployment argocd-application-controller --replicas=0 2>&1 || true
  kubectl -n argocd rollout status statefulset argocd-application-controller --timeout=60s 2>&1 || true
  # A Gateway (or an Ingress) owns a real ALB: if the cluster dies first it is orphaned and keeps billing.
  # Routes first, so ExternalDNS removes the records; then the Gateways, which make the controller delete the ALB.
  kubectl delete httproute --all -A --wait=true --timeout=300s 2>&1 || true
  kubectl delete gateway --all -A --wait=true --timeout=300s 2>&1 || true
  kubectl delete ingress --all -A --wait=true --timeout=300s 2>&1 || true
  for s in $(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'); do
    kubectl delete svc -n "${s%/*}" "${s#*/}" --wait=true --timeout=300s || true
  done
  # Wait for the result, not a fixed time (ExternalDNS syncs every 60s), give up after ~5 min
  say "Waiting for the ALB and DNS records to be removed"
  ZONE_ID="$(aws route53 list-hosted-zones --query "HostedZones[?Name=='manovaturi.com.'].Id" --output text | cut -d/ -f3)"
  for _ in $(seq 1 30); do
    ALBS="$(aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[?starts_with(LoadBalancerName,`k8s-`)].LoadBalancerName' --output text)"
    RECS="$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --query "ResourceRecordSets[?Type=='A' && Name!='jenkins.manovaturi.com.' && Name!='manovaturi.com.' && AliasTarget!=null && contains(AliasTarget.DNSName,'k8s-')].Name" --output text)"
    [[ -z "$ALBS" && -z "$RECS" ]] && break
    echo "  still waiting... ALB: ${ALBS:-none}  DNS: ${RECS:-none}"; sleep 10
  done
  [[ -z "$ALBS" && -z "$RECS" ]] || warn "Cleanup not finished. Check ALBs/DNS in the console before relying on the destroy."

  say "2/3 Destroying the EKS layer"
  tg 40-eks destroy -auto-approve
else
  say "EKS cluster not found, skipping."
fi

# GitLab: destroy only the instance layer, the data volume (layer 35) stays
if layer_ready 45-gitlab-server; then
  say "Destroying the GitLab instance (its data volume is kept)"
  tg 45-gitlab-server destroy -auto-approve
fi

if [[ "$KEEP_EDGE" == 0 ]]; then
  # Order matters: ALB rules (35), then the ALB (30), NAT last (the ALB controller needs it)
  say "3/3 Switching off the shared ALB, stopping Jenkins, switching off the NAT gateway"
  if layer_ready 35-gitlab-data; then
    tg 35-gitlab-data apply -input=false -auto-approve -var edge_enabled=false
  fi
  tg 30-cicd apply -input=false -auto-approve -var edge_enabled=false
  JID="$(jenkins_instance_id)"
  if [[ -n "$JID" ]]; then aws ec2 stop-instances --region "$REGION" --instance-ids "$JID" >/dev/null; fi
  tg 10-network apply -input=false -auto-approve -var enable_nat_gateway=false
else
  say '--keep-edge: NAT gateway, shared ALB and Jenkins stay on (about $2.8 a day)'
fi

say "Verifying nothing expensive is left"
bash "$(dirname "$0")/status.sh"
