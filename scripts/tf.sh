#!/usr/bin/env bash
# Run ONE Terraform/Terragrunt command on ONE layer inside the pinned container.
# The Jenkinsfile and your laptop call this same script, so what you test is what CI runs.
#
#   scripts/tf.sh <layer> <command>
#   scripts/tf.sh all fmt             formatting check of every layer
#   scripts/tf.sh 40-eks init         download providers and modules, no backend, no AWS access
#   scripts/tf.sh 40-eks validate     init + validate (same as check)
#   scripts/tf.sh 40-eks check        init, then validate
#   scripts/tf.sh 40-eks lint         tflint with the rules in .tflint.hcl (repo root)
#   scripts/tf.sh 40-eks scan         Trivy security scan of the code (needs no init, no AWS access)
#   scripts/tf.sh 40-eks plan         terragrunt plan against the real state (READ-ONLY, never applies)
#
# fmt/init/validate/check/lint/scan run on a copy of the layer that also holds the files Terragrunt generates
# (providers.tf and versions.tf from terraform/_shared), so they see the same code as a real run.
#
# Settings (environment variables):
#   TF_IMAGE  the Terraform image, pinned to an exact version
#   TG_IMAGE  the Terragrunt image (Terraform + Terragrunt) that plan uses, pinned to an exact version
#   TF_CACHE  where the provider download is shared by all layers (on disk, NOT in /tmp: it is RAM)
#   TF_MEMORY memory limit of each container (default 768m): if Terraform needs more, only that container dies
#   TFLINT_IMAGE, TFLINT_CACHE  the tflint image (pinned) and where its AWS rule plugin is kept between runs
#   TRIVY_IMAGE, TRIVY_CACHE  the Trivy image (pinned) and where its check database is kept between runs
#   TRIVY_EXIT_CODE  0 = report only (default); 1 = the scan fails the run when it finds HIGH or CRITICAL
#   TF_PLAN_ROLE_ARN  the read-only role plan assumes (Jenkins: the role_arn output of 32-ci-plan); unset = your own credentials
#   TF_VARS_DIR  where the variable files that are not in Git live, one <layer>.tfvars per layer (default ~/.weatherapp/tfvars)
#   TF_ROOT   the terraform folder to work on; point it at a clean copy to test like CI does
source "$(dirname "$0")/lib.sh"

# Git Bash on Windows rewrites a path like /tf/45-gitlab-server into C:/Program Files/Git/tf/...; this switches that off (no effect on Linux)
export MSYS_NO_PATHCONV=1

TF_IMAGE="${TF_IMAGE:-hashicorp/terraform:1.16.7}"
TG_IMAGE="${TG_IMAGE:-alpine/terragrunt:1.15.9}"
TF_CACHE="${TF_CACHE:-$HOME/.cache/tf-plugin-cache}"
TF_MEMORY="${TF_MEMORY:-768m}"
TFLINT_IMAGE="${TFLINT_IMAGE:-ghcr.io/terraform-linters/tflint:v0.64.0}"
TFLINT_CACHE="${TFLINT_CACHE:-${TF_CACHE%/*}/tflint-plugins}"
TRIVY_IMAGE="${TRIVY_IMAGE:-ghcr.io/aquasecurity/trivy:0.76.1}"
TRIVY_CACHE="${TRIVY_CACHE:-${TF_CACHE%/*}/trivy-cache}"
TRIVY_EXIT_CODE="${TRIVY_EXIT_CODE:-0}"
TF_ROOT="${TF_ROOT:-$TF}"
TF_VARS_DIR="${TF_VARS_DIR:-$HOME/.weatherapp/tfvars}"

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

list_layers() { find "$TF_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort; }

# tf_docker <folder> <terraform arguments...>
# --memory caps the container and --memory-swap equal to it forbids swap: the AWS provider alone is
# several hundred MB, and on the 2 GB Jenkins server a runaway run must kill its own container,
# never the Jenkins process (that is what happened with seven parallel validates).
# The cache is mounted in EVERY run, not only in init: init leaves links that point into it,
# and a later run without the mount sees them broken ("no package ... cached in .terraform/providers").
tf_docker() {
  local dir="$1"; shift
  docker run --rm -u "$(id -u):$(id -g)" \
    --memory="$TF_MEMORY" --memory-swap="$TF_MEMORY" \
    -e TF_PLUGIN_CACHE_DIR=/plugin-cache \
    -v "$TF_CACHE:/plugin-cache" \
    -v "$dir:/work" -w /work \
    "$TF_IMAGE" "$@"
}

# tflint_docker <folder> <tflint arguments...>
# The rules come from .tflint.hcl at the repo root, the AWS rule plugin from a cache folder:
# without the cache every run would download it from GitHub (which limits anonymous requests).
# HOME=/tmp because the plugin installer verifies signatures and needs a writable home; the
# container user has none.
tflint_docker() {
  local dir="$1"; shift
  docker run --rm -u "$(id -u):$(id -g)" \
    --memory="$TF_MEMORY" --memory-swap="$TF_MEMORY" \
    -e TFLINT_PLUGIN_DIR=/plugins -e HOME=/tmp \
    -v "$TFLINT_CACHE:/plugins" \
    -v "$(dirname "$TF_ROOT")/.tflint.hcl:/config/.tflint.hcl:ro" \
    -v "$dir:/work" -w /work \
    "$TFLINT_IMAGE" --config /config/.tflint.hcl "$@"
}

# trivy_docker <folder>
# Scans the Terraform code of one layer for risky settings (open security groups, wildcard IAM...).
# --tf-exclude-downloaded-modules: the registry modules (eks, vpc) are not ours and are not downloaded
# here (no init), so only our own code is judged. All severities are printed; only HIGH and CRITICAL
# decide the exit code, and TRIVY_EXIT_CODE=0 turns even that off (report only).
# The check database is cached: without it every run downloads it again.
# .trivyignore at the repo root holds the findings we accepted on purpose, each with a reason.
trivy_docker() {
  local dir="$1" mount=() flag=()
  if [[ -f "$(dirname "$TF_ROOT")/.trivyignore" ]]; then
    mount=(-v "$(dirname "$TF_ROOT")/.trivyignore:/config/.trivyignore:ro")
    flag=(--ignorefile /config/.trivyignore)
  fi
  docker run --rm -u "$(id -u):$(id -g)" \
    --memory="$TF_MEMORY" --memory-swap="$TF_MEMORY" \
    -e TRIVY_CACHE_DIR=/cache -e HOME=/tmp \
    -v "$TRIVY_CACHE:/cache" \
    "${mount[@]}" \
    -v "$dir:/work:ro" -w /work \
    "$TRIVY_IMAGE" config . \
    --tf-exclude-downloaded-modules --skip-dirs '**/.terraform' \
    --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL --exit-code "$TRIVY_EXIT_CODE" \
    "${flag[@]}"
}

# plan_credentials: puts AWS credentials for the plan into the environment.
# Jenkins: AWS_ACCESS_KEY_ID... come from assuming the read-only role (one hour, then they are useless).
# This happens on the host, not in the container: the Jenkins instance requires IMDSv2 with one hop, so a
# container cannot read the instance role, and that setting stays. Your laptop: your own credentials.
# xtrace is switched off here so the keys never reach a build log.
plan_credentials() {
  { set +x; } 2>/dev/null
  local keys session
  if [[ -n "${TF_PLAN_ROLE_ARN:-}" ]]; then
    # the session name shows in CloudTrail: it says which build planned (allowed characters only, max 64)
    session="$(printf '%s' "${BUILD_TAG:-tf-plan-$USER}" | tr -c 'A-Za-z0-9+=,.@_-' '-' | cut -c1-64)"
    say "Assuming $TF_PLAN_ROLE_ARN (session $session)"
    keys="$(aws sts assume-role --role-arn "$TF_PLAN_ROLE_ARN" --role-session-name "$session" \
      --duration-seconds 3600 --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)"
    read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<<"$keys"
  else
    warn "TF_PLAN_ROLE_ARN is not set: the plan runs with your own AWS credentials"
    eval "$(aws configure export-credentials --format env)"
  fi
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# tf_plan_docker <layer> <terragrunt arguments...>
# Mounts the whole terraform folder: root.hcl (backend, provider, versions) is in it, and so are the other
# layers that this layer reads (dependency blocks). The keys are passed by NAME (-e NAME), so they are not in
# the docker command line. The variable files that are not in Git (terraform.tfvars is git-ignored) are
# mounted read-only at /vars. Terragrunt writes its working copy to <layer>/.terragrunt-cache.
tf_plan_docker() {
  local layer="$1" mount=(); shift
  [[ -d "$TF_VARS_DIR" ]] && mount=(-v "$TF_VARS_DIR:/vars:ro")
  docker run --rm -u "$(id -u):$(id -g)" \
    --memory="$TF_MEMORY" --memory-swap="$TF_MEMORY" \
    -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION="$REGION" \
    -e TF_IN_AUTOMATION=1 -e TF_PLUGIN_CACHE_DIR=/plugin-cache -e HOME=/tmp \
    -v "$TF_CACHE:/plugin-cache" \
    -v "$TF_ROOT:/tf" "${mount[@]}" -w "/tf/$layer" \
    "$TG_IMAGE" terragrunt "$@"
}

# static_copy <layer>: a throw-away copy of the layer plus the files Terragrunt would generate there, so that
# validate, tflint and Trivy judge the real code. It is removed when the script ends. Sets STATIC_DIR.
# The versions file is the one root.hcl names for the layer (versions_files), else _shared/versions.tf.tpl.
STATIC_DIRS=()
cleanup_static() { local d; for d in "${STATIC_DIRS[@]}"; do rm -rf "$d"; done; }
static_copy() {
  local layer="$1" shared="$TF_ROOT/_shared" tmp versions=versions.tf.tpl
  [[ -f "$shared/providers.tf.tpl" ]] || { warn "No $shared/providers.tf.tpl"; exit 2; }
  tmp="$(mktemp -d "${TF_CACHE%/*}/tf-static.XXXXXX")"
  STATIC_DIRS+=("$tmp")
  # the layer's own files; not Terraform's or Terragrunt's working folders, not the secrets
  tar -C "$TF_ROOT/$layer" --exclude='.terraform' --exclude='.terragrunt-cache' --exclude='terraform.tfvars' --exclude='*.tfstate*' -cf - . | tar -C "$tmp" -xf -
  # root.hcl: versions_files = { "30-cicd" = "versions-http.tf" }
  versions="$(grep -oE "\"$layer\" *= *\"versions[a-z-]*\.tf\.tpl\"" "$TF_ROOT/root.hcl" | sed 's/.*= *"\(.*\)"/\1/' || true)"
  versions="${versions:-versions.tf.tpl}"
  sed "s/LAYER_NAME/$layer/" "$shared/providers.tf.tpl" >"$tmp/providers.tf"
  cp "$shared/$versions" "$tmp/versions.tf"
  STATIC_DIR="$tmp"
}

main() {
  [[ $# -eq 2 ]] || usage
  local layer="${1%/}" cmd="$2"

  [[ "$TF_ROOT" = /* ]] || { warn "TF_ROOT must be an absolute path (docker needs one): $TF_ROOT"; exit 2; }
  mkdir -p "$TF_CACHE" "$TFLINT_CACHE" "$TRIVY_CACHE"
  trap cleanup_static EXIT

  if [[ "$layer" == all ]]; then
    case "$cmd" in
      fmt) tf_docker "$TF_ROOT" fmt -check -recursive -diff . ;;
      *)   warn "'all' only supports fmt"; exit 2 ;;
    esac
    return
  fi

  if [[ ! -d "$TF_ROOT/$layer" ]]; then
    warn "No layer '$layer' in $TF_ROOT. Layers:"
    list_layers | sed 's/^/   /'
    exit 2
  fi

  local dir="$TF_ROOT/$layer"
  case "$cmd" in
    init|validate|check|lint|scan) static_copy "$layer"; dir="$STATIC_DIR" ;;
  esac
  case "$cmd" in
    fmt)      tf_docker "$dir" fmt -check -recursive -diff . ;;
    init)     tf_docker "$dir" init -backend=false -input=false ;;
    validate) tf_docker "$dir" init -backend=false -input=false >/dev/null; tf_docker "$dir" validate ;;
    check)
      say "$layer: init"
      tf_docker "$dir" init -backend=false -input=false >/dev/null
      say "$layer: validate"
      tf_docker "$dir" validate
      ;;
    lint)
      [[ -f "$(dirname "$TF_ROOT")/.tflint.hcl" ]] || { warn "No .tflint.hcl at the repo root"; exit 2; }
      tflint_docker "$dir" --init >/dev/null
      tflint_docker "$dir"
      ;;
    scan)     trivy_docker "$dir" ;;
    plan)
      local varfile=() rc=0
      [[ -f "$TF_VARS_DIR/$layer.tfvars" ]] && varfile=(-var-file="/vars/$layer.tfvars")
      plan_credentials
      say "$layer: plan with the real backend (changes nothing; Terragrunt runs init first)"
      # -detailed-exitcode: 0 = nothing to do, 2 = changes (normal, it is only a report), 1 = error
      tf_plan_docker "$layer" plan --non-interactive -input=false -lock-timeout=60s -detailed-exitcode "${varfile[@]}" || rc=$?
      case "$rc" in
        0) say "$layer: no changes" ;;
        2) say "$layer: the plan has changes (a report, not a failure)" ;;
        *) warn "$layer: terraform plan failed (exit $rc)"; exit "$rc" ;;
      esac
      ;;
    *) warn "Unknown command '$cmd' (fmt, init, validate, check, lint, scan, plan)"; exit 2 ;;
  esac
}

main "$@"
