# Runbook

Region `eu-west-1`, cluster `weatherapp`. Commands run from the repository root unless noted. GitLab projects keep the original
`weatherapp-source`, `weatherapp-gitops` and `weatherapp-infra` names; the GitHub repositories are `weather-service`,
`eks-platform-gitops` and `eks-platform-infra`.

The environment is built from Git at the start of a session and destroyed at the end. Between sessions only the persistent layer
(`10-network` without NAT, `20-persistent`, `35-gitlab-data`) remains: disks, snapshots, DNS, WAF, KMS key and the ECR repository.

## 1. Workstation prerequisites

```bash
terraform version && terragrunt --version && aws --version
kubectl version --client && helm version --short && docker --version
aws sts get-caller-identity
```

Operator IP ranges that may reach Jenkins, GitLab and the ALB are not committed. Create the untracked tfvars per layer:

```bash
curl -fsS https://checkip.amazonaws.com
printf 'allowed_cidrs = ["203.0.113.10/32"]\n' > terraform/30-cicd/terraform.tfvars
cp terraform/30-cicd/terraform.tfvars terraform/40-eks/terraform.tfvars
```

Runtime secrets live in `~/.weatherapp/` (mode 700, files mode 600) and are read from files or stdin, never from the command line:

```bash
mkdir -p ~/.weatherapp && chmod 700 ~/.weatherapp
openssl rand -hex 16 | tr -d '\n' > ~/.weatherapp/postgres-password
openssl rand -hex 16 | tr -d '\n' > ~/.weatherapp/mongo-password
read -r -s -p "Grafana admin password: " V; echo; printf '%s' "$V" > ~/.weatherapp/grafana-password; unset V
read -r -s -p "Slack webhook URL: " V; echo; printf '%s' "$V" > ~/.weatherapp/slack-webhook; unset V
read -r -s -p "GitLab read-only token: " V; echo; printf '%s' "$V" > ~/.weatherapp/gitlab-readonly-token; unset V
chmod 600 ~/.weatherapp/*
```

## 2. First build (once)

`00-bootstrap` creates the Terraform state bucket with local state (plain `terraform`, run once, never re-applied). The other layers apply in numeric order through `scripts/apply.sh`, which wraps `terragrunt apply` with the shared backend and provider templates.

```bash
printf 'budget_email = "you@example.com"\n' > terraform/20-persistent/terraform.tfvars
(cd terraform/00-bootstrap && terraform init && terraform apply)   # state bucket
scripts/apply.sh 10-network -var enable_nat_gateway=true
scripts/apply.sh 20-persistent     # ECR, KMS, WAF, ACM, Vault data volume, budget alarm
```

## 3. Start a session

```bash
export AWS_REGION=eu-west-1 CLUSTER=weatherapp

scripts/apply.sh 10-network  -var enable_nat_gateway=true
scripts/apply.sh 30-cicd     -var edge_enabled=true
scripts/apply.sh 35-gitlab-data -var edge_enabled=true
scripts/apply.sh 45-gitlab-server
(cd terraform/45-gitlab-server && terragrunt plan)      # expect: No changes

JENKINS_ID=$(aws ec2 describe-instances --region $AWS_REGION \
  --filters Name=tag:Name,Values=weatherapp-jenkins Name=instance-state-name,Values=stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text)
aws ec2 start-instances --region $AWS_REGION --instance-ids $JENKINS_ID

scripts/apply.sh 40-eks
aws eks update-kubeconfig --name $CLUSTER --region $AWS_REGION
kubectl get nodes -L topology.kubernetes.io/zone
```

### Argo CD bootstrap

Run from `eks-platform-gitops` checked out next to this repository.

```bash
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm upgrade --install argocd argo/argo-cd --version 10.10.5 -n argocd --create-namespace --wait --timeout 10m \
  -f ../eks-platform-gitops/bootstrap/argocd-values.yaml \
  --set "configs.secret.argocdServerAdminPassword=$(tr -d '\r\n' < ~/.weatherapp/argocd-password-hash)"

tr -d '\r\n' < ~/.weatherapp/gitlab-readonly-token > ~/.weatherapp/.tmp-token
kubectl -n argocd create secret generic gitops-repo \
  --from-literal=type=git --from-literal=url=https://gitlab.manovaturi.com/weatherapp/weatherapp-gitops.git \
  --from-literal=username=oauth2 --from-file=password=$HOME/.weatherapp/.tmp-token \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret gitops-repo argocd.argoproj.io/secret-type=repository --overwrite
rm ~/.weatherapp/.tmp-token

for ns in postgres mongo weatherapp weatherapp-dev monitoring; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done

kubectl apply -f ../eks-platform-gitops/bootstrap/root-app.yaml
kubectl -n argocd get applications
```

The root application renders every AppProject, ApplicationSet and platform Application in sync-wave order
(Istio ambient, Vault, Kyverno, monitoring, workloads).

## 4. Vault initialisation (once per Vault volume)

Vault auto-unseals through the KMS key from `20-persistent`. Initialisation only creates the recovery key and root token.

```bash
scripts/vault-bootstrap.sh          # wraps the steps below

kubectl -n vault exec vault-0 -- vault operator init -recovery-shares=1 -recovery-threshold=1 > ~/.weatherapp/vault-init
chmod 600 ~/.weatherapp/vault-init
kubectl -n vault exec -it vault-0 -- vault login -no-print

V="kubectl -n vault exec -i vault-0 -- vault"
$V secrets enable -path=kv -version=2 kv
$V policy write vso-read - <<'POLICY'
path "kv/data/postgres"      { capabilities = ["read"] }
path "kv/data/mongo"         { capabilities = ["read"] }
path "kv/data/grafana"       { capabilities = ["read"] }
path "kv/data/grafana-slack" { capabilities = ["read"] }
POLICY
$V auth enable kubernetes
$V write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"
$V write auth/kubernetes/role/vso bound_service_account_names=default \
  bound_service_account_namespaces="postgres,mongo,weatherapp,weatherapp-dev,monitoring" policies=vso-read ttl=1h

tr -d '\r\n' < ~/.weatherapp/postgres-password | $V kv put kv/postgres username=weatherapp password=-
tr -d '\r\n' < ~/.weatherapp/mongo-password    | $V kv put kv/mongo username=weatherapp password=-
tr -d '\r\n' < ~/.weatherapp/grafana-password  | $V kv put kv/grafana admin-user=admin admin-password=-
tr -d '\r\n' < ~/.weatherapp/slack-webhook     | $V kv put kv/grafana-slack SLACK_WEBHOOK_URL=-
kubectl -n vault exec vault-0 -- rm -f /home/vault/.vault-token
```

Vault Secrets Operator then syncs `kv/*` into Kubernetes Secrets in the namespaces bound to the `vso` role.
Rotate the root token after initialisation with `vault token create -orphan -policy=root`, then revoke the old accessor.

## 5. Verify

```bash
kubectl get nodes -L topology.kubernetes.io/zone     # 1 node Ready
kubectl -n argocd get applications                   # all Synced and Healthy
kubectl get pods -A                                  # nothing in Pending or CrashLoopBackOff
kubectl get vaultstaticsecret -A                     # SYNCED True
curl -s https://weather.manovaturi.com/healthz
curl -s https://weather-dev.manovaturi.com/healthz
```

UIs are not exposed publicly. Use port-forwards:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n monitoring port-forward svc/grafana 3000:80
kubectl -n monitoring port-forward svc/mimir 9009:9009
```

## 6. End a session

Order matters: Argo CD must stop reconciling and the AWS Load Balancer Controller must release its load balancers before
Terraform removes the VPC, otherwise the destroy hangs on orphaned ENIs and security groups.

```bash
aws eks update-kubeconfig --name weatherapp --region eu-west-1
kubectl -n argocd scale statefulset argocd-application-controller --replicas=0
kubectl delete httproute --all -A --wait=true --timeout=300s
kubectl delete gateway   --all -A --wait=true --timeout=300s
kubectl delete ingress   --all -A --wait=true --timeout=300s

(cd terraform/40-eks && terragrunt destroy -auto-approve)
(cd terraform/45-gitlab-server && terragrunt destroy -auto-approve)

(cd terraform/35-gitlab-data && terragrunt apply -input=false -auto-approve -var edge_enabled=false)
(cd terraform/30-cicd && terragrunt apply -input=false -auto-approve -var edge_enabled=false)
aws ec2 stop-instances --region eu-west-1 --instance-ids "$JENKINS_ID"
(cd terraform/10-network && terragrunt apply -input=false -auto-approve -var enable_nat_gateway=false)
```

Confirm nothing billable is left:

```bash
scripts/status.sh
aws ec2 describe-nat-gateways --region eu-west-1 --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId' --output text
aws elbv2 describe-load-balancers --region eu-west-1 --query 'LoadBalancers[].LoadBalancerName' --output text
aws ec2 describe-addresses --region eu-west-1 --query 'Addresses[].PublicIp' --output text
```

## 7. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `kube_*` queries return nothing in Grafana | Alloy renames the `namespace` label to `exported_namespace` | set `honor_labels = true` on the kube-state-metrics scrape |
| Slack alerts never arrive | webhook secret stored with a trailing newline | recreate the value with `tr -d '\r\n'` |
| Dashboards lost after a Grafana restart | built in the UI only (Grafana has no disk) | export as classic JSON into `charts/grafana-dashboards/dashboards/` |
| `kubectl get secret NAME -A` refused | cluster-wide secret listing is blocked by policy | `kubectl get secret -A --field-selector metadata.name=NAME` |
| Destroy hangs on VPC deletion | load balancer or ENI left by the controller | delete Gateway, HTTPRoute and Ingress objects first (section 6) |
| Vault pod sealed after volume reuse | stale raft data | `kubectl -n vault exec vault-0 -- sh -c 'rm -rf /vault/data/raft /vault/data/vault.db'`, delete the pod, re-run section 4 |

## 8. Alerts

Grafana-managed rules provisioned from `eks-platform-gitops/platform/monitoring/grafana/values.yaml`; "no data" counts as OK so the
nightly shutdown does not page.

| Alert | Condition | First check |
| --- | --- | --- |
| App down | no ready `weatherapp` target for 3 min | `kubectl -n weatherapp get pods` and the pod log |
| Container restarted | restart within 15 min | `kubectl describe pod`, last state (OOMKilled) |
| Memory near limit | container above 85% of limit for 10 min | raise the limit in chart values |
| Node memory high | node above 85% of allocatable for 10 min | namespaces by memory in Grafana |
| High 5xx ratio | more than 5% 5xx for 5 min | app log, then databases |
| Pod not ready | not ready for 10 min | `kubectl describe pod`, probes and events |
