#!/usr/bin/env bash
# START OF WORK DAY: bring everything up. Safe to re-run.
# Overnight nothing runs: no cluster, GitLab, NAT or shared ALB, and Jenkins is stopped.
# Usage: up.sh                  -> the complete project: prod, dev and monitoring
#        up.sh --no-gitlab      -> do not create the GitLab instance
#        up.sh --no-monitoring -> Argo CD skips argocd/platform/monitoring (no Mimir, Alloy, Grafana)
#        up.sh --lean           -> same as --no-monitoring (the skinny day: everything else runs, including the dev app)
#        up.sh --no-vault       -> do not initialise, configure and seed Vault (scripts/vault-bootstrap.sh does it by hand)
# The flags can be combined. Re-running with other flags on a running cluster prunes or restores the Applications.
# Read it from the bottom: main() lists the steps in order.
source "$(dirname "$0")/lib.sh"
require_tools aws kubectl terraform terragrunt helm curl

# If anything fails halfway, say so. Every step is safe to repeat.
announce_failure() {
  local status=$?
  if [[ "$status" -ne 0 && -z "${USAGE_ERROR:-}" ]]; then
    echo
    warn "up.sh stopped before it finished. Read the error above, fix it and run up.sh again (it is safe to repeat). Whatever it already created keeps billing until down.sh."
  fi
}
trap announce_failure EXIT

GITLAB=1
NO_MONITORING=0
NO_VAULT=0

# Step 5 reads these. The repo token is read-only (Code: Download) and lives outside every repo.
TOKEN_FILE="$SECRETS_DIR/gitlab-readonly-token"
ROOT_APP="$ROOT/../weatherapp-gitops/bootstrap/root-app.yaml"
ARGOCD_CHART_VERSION="10.10.5"
ARGOCD_VALUES="$ROOT/../weatherapp-gitops/bootstrap/argocd-values.yaml" # no dex, no notifications, a memory limit for the controller

# Reading the command line

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --no-gitlab) GITLAB=0 ;;
      --no-monitoring) NO_MONITORING=1 ;;
      --lean) NO_MONITORING=1 ;;
      --no-vault) NO_VAULT=1 ;;
      *) echo "Unknown option: $arg (supported: --no-gitlab, --no-monitoring, --lean, --no-vault)"; USAGE_ERROR=1; exit 1 ;;
    esac
  done
}

# Step 1 and 2: who am I, and may my IP reach the ALB and the EKS API?

check_identity() {
  say "1/5 Checking AWS identity"
  aws sts get-caller-identity --query Arn --output text
}

check_public_ip() {
  say "2/5 Is your public IP inside allowed_cidrs? (ALB and the EKS API only allow those ranges)"
  local my_ip layer file current range changed_ip=0
  my_ip="$(curl -fsS https://checkip.amazonaws.com | tr -d '\r\n')"
  for layer in 30-cicd 40-eks; do
    file="$TF/$layer/terraform.tfvars"
    current="$(read_allowed_cidrs "$file")"
    # an old file with the single allowed_cidr is rewritten as a list: Terraform only knows allowed_cidrs now
    if [[ -n "$current" ]] && grep -q '^allowed_cidr *=' "$file"; then
      # shellcheck disable=SC2086  # $current is a space-separated list on purpose
      write_allowed_cidrs "$file" $current
      say "$layer/terraform.tfvars: the single allowed_cidr was converted to the list allowed_cidrs"
    fi
    if [[ -z "$current" ]] || ! ip_in_any "$my_ip" "$current"; then
      warn "$layer/terraform.tfvars allowed_cidrs (${current:-missing}) does not contain your current IP ($my_ip)"
      # the ISP rotates the address inside its range, so a single /32 locks you out at random.
      # The new range is ADDED: the ranges of your other places (home, office) stay.
      range="$(ip_range23 "$my_ip")"
      if ask "Add the range $range to the list (the others stay)?"; then
        # shellcheck disable=SC2086
        write_allowed_cidrs "$file" $current $range
        changed_ip=1
      fi
    fi
  done
  if [[ "$changed_ip" == 1 ]]; then
    say "New IP saved. It reaches the ALB and the rules in the next step."
  fi
}

# Step 3: network, load balancer, Jenkins

switch_on_network_and_edge() {
  say "3/5 Switching on the NAT gateway and the shared ALB, then starting Jenkins"
  # Both bill by the hour. The NAT gets a new IP each time: NAT, then ALB (30), then GitLab rules (35)
  tg 10-network apply -input=false -auto-approve -var enable_nat_gateway=true
  tg 30-cicd apply -input=false -auto-approve -var edge_enabled=true
  if layer_ready 35-gitlab-data; then
    tg 35-gitlab-data apply -input=false -auto-approve -var edge_enabled=true
  fi
  warn "The jenkins. and gitlab. DNS names were just recreated. If a name does not open for a few minutes, that is resolver caching, not a fault."
}

start_jenkins() {
  local jenkins_id state
  jenkins_id="$(jenkins_instance_id)"
  state="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$jenkins_id" --query 'Reservations[0].Instances[0].State.Name' --output text)"
  if [[ "$state" == "stopped" ]]; then aws ec2 start-instances --region "$REGION" --instance-ids "$jenkins_id" >/dev/null; fi
  echo "Jenkins: $state -> running  (https://jenkins.manovaturi.com, ready in ~2 min)"
}

create_gitlab_server() {
  if [[ "$GITLAB" == 1 ]]; then
    if layer_ready 45-gitlab-server; then
      say "GitLab: creating the instance (it boots and re-attaches its data volume in ~5 min, while EKS is created)"
      tg 45-gitlab-server apply -auto-approve
    else
      warn "GitLab layers not set up yet (run terragrunt apply in 35-gitlab-data, then 45-gitlab-server): skipping GitLab."
    fi
  fi
}

# Step 4: the cluster

create_cluster() {
  say "4/5 Creating the EKS cluster (about 12 minutes)"
  tg 40-eks apply -auto-approve
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
  kubectl get nodes

  if [[ "$GITLAB" == 0 ]]; then
    warn "--no-gitlab: Argo CD reads the gitops repo from GitLab, so it cannot sync until GitLab is up (run up.sh without the flag)."
  fi
}

# Step 5: Argo CD and the Secrets from local files, Argo CD installs the rest from Git

install_argocd() {
  helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
  helm repo update argo >/dev/null
  # Fixed admin password: a bcrypt hash in a local file, so it survives down/up
  local pw_file="$SECRETS_DIR/argocd-password-hash"
  ARGOCD_EXTRA=()
  if [[ -s "$pw_file" ]]; then
    ARGOCD_EXTRA=(--set "configs.secret.argocdServerAdminPassword=$(tr -d '\r\n' < "$pw_file")")
  else
    warn "No $pw_file: Argo CD will generate a random admin password (Secret argocd-initial-admin-secret)."
  fi
  helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART_VERSION" -n argocd --create-namespace --wait --timeout 10m     -f "$ARGOCD_VALUES" "${ARGOCD_EXTRA[@]}"
}

create_repo_secret() {
  # The credential Argo CD uses to read the gitops repo (the label is what makes it a repository credential)
  apply_secret argocd gitops-repo argocd.argoproj.io/secret-type=repository -- \
    type=git url=https://gitlab.manovaturi.com/weatherapp/weatherapp-gitops.git username=oauth2 password=@"$TOKEN_FILE"
}

create_database_secrets() {
  # The database namespaces and, with --no-vault, the passwords. Normally the Vault Secrets Operator makes the Secrets from Vault
  # (charts/vault-secrets in the gitops repo), so only the namespaces are made here. Dev shares the production databases, so
  # weatherapp-dev needs the same two Secrets as weatherapp.
  local db db_file ns
  for db in postgres mongo; do
    db_file="$SECRETS_DIR/$db-password"
    for ns in "$db" weatherapp weatherapp-dev; do
      ensure_namespace "$ns"
      if [[ "$NO_VAULT" == 0 ]]; then continue; fi
      if [[ -s "$db_file" ]]; then
        apply_secret "$ns" "$db-credentials" -- username=weatherapp password=@"$db_file"
      else
        warn "No $db password at $db_file: the $db database and the app's use of it will not start until the $db-credentials Secrets exist."
      fi
    done
  done
}

create_grafana_secret() {
  # Grafana's admin login. The Grafana chart reads it through admin.existingSecret.
  local pw_file="$SECRETS_DIR/grafana-password"
  ensure_namespace monitoring
  if [[ -s "$pw_file" ]]; then
    apply_secret monitoring grafana-admin -- admin-user=admin admin-password=@"$pw_file"
  else
    warn "No Grafana password at $pw_file: Grafana will not start until the grafana-admin Secret exists."
  fi
}

create_grafana_slack_secret() {
  # The Slack webhook that Grafana alerting posts to. The chart exposes it as SLACK_WEBHOOK_URL (envFromSecrets, optional).
  local hook_file="$SECRETS_DIR/slack-webhook"
  ensure_namespace monitoring
  if [[ -s "$hook_file" ]]; then
    apply_secret monitoring grafana-slack -- SLACK_WEBHOOK_URL=@"$hook_file"
  else
    warn "No Slack webhook at $hook_file: Grafana starts, but its alerts cannot reach Slack."
  fi
}

apply_root_apps() {
  # Which folders of argocd/ the root Application skips. The file in Git is never changed: a patched copy is rendered
  # offline (--local) and applied once. With no exclusion the plain file is applied, which also clears an exclusion
  # left by an earlier lean run (apply removes fields that were in the last applied version and are not in this one).
  # Only explicit Applications can be skipped this way: the workloads (app, databases, dev) come from one ApplicationSet.
  local excludes=()
  if [[ "$NO_MONITORING" == 1 ]]; then excludes+=("platform/monitoring/*"); fi
  if [[ "${#excludes[@]}" -eq 0 ]]; then
    kubectl apply -f "$ROOT_APP"
  else
    local joined patch
    joined="$(IFS=,; echo "${excludes[*]}")"
    # the glob list is {a,b}; one entry still works in braces
    patch="{\"spec\":{\"source\":{\"directory\":{\"exclude\":\"{$joined}\"}}}}"
    say "Argo CD root skips: {$joined}"
    kubectl patch --local -f "$ROOT_APP" --type merge -p "$patch" -o yaml | kubectl apply -f -
  fi
  kubectl -n argocd get applications
}

bootstrap_argocd() {
  say "5/5 Bootstrapping Argo CD (it then installs the controllers and the app from Git)"
  if [[ ! -s "$TOKEN_FILE" ]]; then
    warn "No GitLab read-only token at $TOKEN_FILE: skipping Argo CD bootstrap."
    warn "Create it (a file containing only the token), then re-run this script. It is safe to re-run."
    return
  fi
  if [[ ! -f "$ROOT_APP" ]]; then
    warn "Not found: $ROOT_APP (expected weatherapp-gitops next to weatherapp-infra). Skipping Argo CD bootstrap."
    return
  fi
  install_argocd
  create_repo_secret
  create_database_secrets
  if [[ "$NO_MONITORING" == 0 ]]; then
    create_grafana_secret
    create_grafana_slack_secret
  fi
  apply_root_apps
}

# Step 6: Vault. Argo CD installs it; this initialises it the first time and configures and seeds what is missing.

bootstrap_vault() {
  if [[ "$NO_VAULT" == 1 ]]; then return; fi
  say "Vault: init, configure, seed (Argo CD installs Vault first; this waits up to 10 minutes for the pod)"
  # A failure here must not undo the day: Vault can be repaired later with scripts/vault-bootstrap.sh
  bash "$(dirname "$0")/vault-bootstrap.sh" || warn "Vault bootstrap did not finish. Run scripts/vault-bootstrap.sh after reading the message above."
}

# The whole script, in order

main() {
  parse_args "$@"
  check_identity
  check_public_ip
  switch_on_network_and_edge
  start_jenkins
  create_gitlab_server
  create_cluster
  bootstrap_argocd
  bootstrap_vault
  say "Done. Argo CD installs the controllers and the app in a few minutes: kubectl -n argocd get applications"
}

main "$@"
