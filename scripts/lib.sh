#!/usr/bin/env bash
# Shared helpers for up.sh / down.sh / status.sh
set -euo pipefail

REGION="eu-west-1"
CLUSTER="weatherapp"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/terraform"

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
ask()  { read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

# tg LAYER ARGS...  runs terragrunt in a layer, e.g.  tg 10-network apply -auto-approve
# Terragrunt generates the backend, the provider and versions.tf and reads the other layers' outputs itself.
tg() { local layer="$1"; shift; (cd "$TF/$layer" && terragrunt "$@"); }
# true when the layer is set up (it has a terragrunt.hcl); terragrunt runs init by itself on the first command
layer_ready() { [[ -f "$TF/$1/terragrunt.hcl" ]]; }

# ip_in_cidr 203.0.113.22 203.0.112.0/23  -> exit 0 if the IP is inside the range
ip_to_int() { local a b c d; IFS=. read -r a b c d <<<"$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
# the /23 around an IP, e.g. 203.0.113.22 -> 203.0.112.0/23
ip_range23() { local n; n=$(( $(ip_to_int "$1") & 0xFFFFFE00 )); printf '%d.%d.%d.%d/23' $(( (n >> 24) & 255 )) $(( (n >> 16) & 255 )) $(( (n >> 8) & 255 )) $(( n & 255 )); }
ip_in_cidr() {
  local ip="$1" net="${2%/*}" bits="${2#*/}"
  [[ "$2" == */* ]] || bits=32
  local mask=$(( bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
  (( ($(ip_to_int "$ip") & mask) == ($(ip_to_int "$net") & mask) ))
}
# ip_in_any 203.0.113.22 "198.51.100.0/23 203.0.112.0/23"  -> exit 0 if the IP is inside any range
ip_in_any() { local c; for c in $2; do ip_in_cidr "$1" "$c" && return 0; done; return 1; }

# The ranges in a terraform.tfvars, on one line separated by spaces. Reads allowed_cidrs = ["a", "b"]
# and also the old single allowed_cidr = "a" (so an old file is still understood and gets converted).
read_allowed_cidrs() {
  [[ -f "$1" ]] || return 0
  tr -d '\r' < "$1" | sed -n -e 's/^allowed_cidrs *= *\[\(.*\)\].*/\1/p' -e 's/^allowed_cidr *= *"\(.*\)".*/\1/p' | tr -d '"' | tr ',' ' ' | xargs
}
# write_allowed_cidrs FILE RANGE...  -> allowed_cidrs = ["RANGE", ...]
write_allowed_cidrs() {
  local file="$1" list="" c; shift
  for c in "$@"; do list+="${list:+, }\"$c\""; done
  echo "allowed_cidrs = [$list]" > "$file"
}

jenkins_instance_id() {
  aws ec2 describe-instances --region "$REGION" \
    --filters Name=tag:Name,Values=weatherapp-jenkins Name=instance-state-name,Values=running,stopped,stopping,pending \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

cluster_exists() {
  aws eks describe-cluster --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1
}

# ---------- Secrets and tools ----------

SECRETS_DIR="$HOME/.weatherapp" # one value per file, outside every repo (the list is in docs/runbook.md)

die() { warn "$*"; exit 1; }

# require_tools aws kubectl ...: stop with a clear message when a tool is missing. The usual cause on Windows is the wrong shell
# (WSL's bash or the MSYS2 window have none of these tools): use Git Bash, or the `bash` function of the PowerShell profile.
require_tools() {
  local missing=() tool
  for tool in "$@"; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    die "Not found in this shell: ${missing[*]}. On Windows use Git Bash (not WSL's bash and not the MSYS2 window)."
  fi
}

# ensure_namespace NAME: create it if it does not exist
ensure_namespace() { kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f -; }

# apply_secret NAMESPACE NAME [label=value ...] -- KEY=VALUE | KEY=@FILE ...
# Creates or updates a Secret. A value that starts with @ is read from that file with the trailing newline removed (a newline in a
# password means it never matches). The values travel through a pipe, never on a command line.
apply_secret() {
  local ns="$1" name="$2" labels=() lines=() item key value label bs='\' dq='"'
  shift 2
  while [[ $# -gt 0 && "$1" != "--" ]]; do labels+=("$1"); shift; done
  shift
  for item in "$@"; do
    key="${item%%=*}"; value="${item#*=}"
    if [[ "$value" == @* ]]; then value="$(tr -d '\r\n' < "${value#@}")"; fi
    value="${value//"$bs"/"$bs$bs"}"; value="${value//"$dq"/"$bs$dq"}" # YAML double quotes: escape the backslash first, then the quote
    lines+=("  $key: \"$value\"")
  done
  {
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\n' "$name" "$ns"
    if [[ "${#labels[@]}" -gt 0 ]]; then
      printf '  labels:\n'
      for label in "${labels[@]}"; do printf '    %s: "%s"\n' "${label%%=*}" "${label#*=}"; done
    fi
    printf 'stringData:\n'
    printf '%s\n' "${lines[@]}"
  } | kubectl apply -f -
}
