#!/usr/bin/env bash
# VAULT BOOTSTRAP: initialise, configure and seed Vault, each step only when it is missing. Safe to repeat.
# Usage: vault-bootstrap.sh            -> init if needed, configure, seed what is missing
#        vault-bootstrap.sh --reseed   -> also overwrite the four paths with the values in ~/.weatherapp/
# Vault keeps its data on an EBS volume, so on a normal day this finds Vault initialised and unsealed and does almost nothing.
# up.sh calls it at the end; run it by hand after a Vault pod was recreated or a value file changed.
# The manual version of every step is in docs/runbook.md, section 4.
source "$(dirname "$0")/lib.sh"

# Git Bash on Windows rewrites arguments that start with / (like /home/vault) into Windows paths. Switch that off.
export MSYS_NO_PATHCONV=1

NS=vault
POD=vault-0
INIT_FILE="$SECRETS_DIR/vault-init"
RESEED=0
# VSO logs in with the ServiceAccount "default" of the namespace of each VaultStaticSecret (not of its own namespace), so the
# role must allow every namespace that receives a Secret. Keep this list equal to defaultAuthMethod.allowedNamespaces in
# weatherapp-gitops/platform/vault/vault-secrets-operator/values.yaml.
VSO_NAMESPACES="postgres,mongo,weatherapp,weatherapp-dev,monitoring"

for arg in "$@"; do
  case "$arg" in
    --reseed) RESEED=1 ;;
    *) echo "Unknown option: $arg (supported: --reseed)"; exit 1 ;;
  esac
done

# Two ways to run the vault CLI inside the pod. The second passes standard input (a policy, a secret value).
v()  { kubectl -n "$NS" exec "$POD" -- vault "$@" </dev/null; }
vi() { kubectl -n "$NS" exec -i "$POD" -- vault "$@"; }

# The login token lives in the pod (~/.vault-token) only while this script runs.
cleanup() { kubectl -n "$NS" exec "$POD" -- rm -f /home/vault/.vault-token </dev/null >/dev/null 2>&1 || true; }
trap cleanup EXIT

wait_for_pod() {
  say "Vault 1/5: waiting for the pod $POD (Argo CD installs it, which can take a few minutes after up.sh)"
  require_tools kubectl
  local i phase
  for i in $(seq 1 60); do
    phase="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>&1 || true)"
    if [[ "$phase" == "Running" ]]; then return 0; fi
    echo "  attempt $i of 60: ${phase:-no answer}"
    sleep 10
  done
  warn "The pod $POD is not Running after 10 minutes. Check: kubectl -n argocd get applications vault vault-storage"
  exit 1
}

vault_status() {
  # `vault status` exits 2 when Vault is sealed or not initialised (and the script runs with pipefail), so the exit code
  # is ignored here; the JSON it prints says which state Vault is in.
  v status -format=json 2>/dev/null || true
}

vault_initialized() { grep -q '"initialized": true' <<<"$(vault_status)"; }

vault_sealed() { grep -q '"sealed": true' <<<"$(vault_status)"; }

initialise() {
  say "Vault 2/5: initialising (once per volume)"
  if vault_initialized; then echo "Already initialised: skipping."; return; fi
  if [[ -s "$INIT_FILE" ]]; then
    # An init file exists but Vault is empty (a new volume): keep the old file, it may still matter.
    mv "$INIT_FILE" "$INIT_FILE.old-$(date +%Y%m%d-%H%M%S)"
    warn "Vault is not initialised but $INIT_FILE existed: it was renamed to vault-init.old-*."
  fi
  # The recovery key and the root token go to the file, never to the screen.
  v operator init -recovery-shares=1 -recovery-threshold=1 > "$INIT_FILE"
  chmod 600 "$INIT_FILE" 2>/dev/null || true
  warn "Vault initialised. The recovery key and root token are in $INIT_FILE: back it up (password manager), never paste it anywhere."
}

wait_unsealed() {
  say "Vault 3/5: waiting for the KMS auto-unseal"
  local i
  for i in $(seq 1 30); do
    if ! vault_sealed; then echo "Unsealed."; return 0; fi
    sleep 5
  done
  warn "Vault is still sealed after 150 seconds. Check the log (kubectl -n vault logs $POD) for AWS or KMS errors (the IRSA annotation must be the ROLE arn)."
  exit 1
}

login() {
  say "Vault 4/5: logging in with the root token (kept in the pod only until this script ends)"
  if [[ ! -s "$INIT_FILE" ]]; then
    warn "No $INIT_FILE: copy it from the machine that initialised Vault (docs/runbook.md, section 4)."
    exit 1
  fi
  # The token goes through stdin, never on a command line.
  awk '/Initial Root Token:/ {printf "%s", $NF}' "$INIT_FILE" | vi login -no-print -
}

configure() {
  say "Vault 5/5: configuring (kv, policy, Kubernetes auth) and seeding"
  v secrets list -format=json | grep -q '"kv/"' || v secrets enable -path=kv -version=2 kv

  # What a login with the role "vso" may read: the four paths and nothing else
  vi policy write vso-read - <<'EOF'
path "kv/data/postgres"     { capabilities = ["read"] }
path "kv/data/mongo"        { capabilities = ["read"] }
path "kv/data/grafana"      { capabilities = ["read"] }
path "kv/data/grafana-slack" { capabilities = ["read"] }
EOF

  v auth list -format=json | grep -q '"kubernetes/"' || v auth enable kubernetes
  # Vault runs inside the cluster: it checks tokens with its own ServiceAccount and the cluster CA
  v write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"
  v write auth/kubernetes/role/vso \
    bound_service_account_names=default \
    bound_service_account_namespaces="$VSO_NAMESPACES" \
    policies=vso-read ttl=1h

  seed_secrets
}

# seed PATH FILE KEY [KEY=VALUE...]: writes kv/PATH; KEY gets its value from FILE (through stdin), the rest are fixed keys
seed() {
  local path="$1" file="$2" key="$3"; shift 3
  if [[ "$RESEED" == 0 ]] && v kv get -format=json "kv/$path" >/dev/null 2>&1; then echo "kv/$path exists: skipping (--reseed overwrites)."; return; fi
  if [[ ! -s "$file" ]]; then warn "No $file: kv/$path was not written."; return; fi
  # one value is read from stdin ("-"), the other keys are plain arguments
  tr -d '\r\n' < "$file" | vi kv put "kv/$path" "$@" "$key=-" >/dev/null
  echo "kv/$path written."
}

seed_secrets() {
  seed postgres     "$SECRETS_DIR/postgres-password" password          username=weatherapp
  seed mongo        "$SECRETS_DIR/mongo-password"    password          username=weatherapp
  seed grafana      "$SECRETS_DIR/grafana-password"  admin-password    admin-user=admin
  seed grafana-slack "$SECRETS_DIR/slack-webhook"    SLACK_WEBHOOK_URL
}

main() {
  wait_for_pod
  initialise
  wait_unsealed
  login
  configure
  say "Vault is ready. Check: kubectl -n vault exec $POD -- vault status"
}

main
