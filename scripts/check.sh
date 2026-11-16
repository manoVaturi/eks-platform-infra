#!/usr/bin/env bash
# Run the pipeline's checks on your laptop BEFORE you push: the same tf.sh commands as Jenkins, in seconds,
# on a clean copy of your working folder (committed or not), so a red build costs you nothing.
#
#   scripts/check.sh                 the layers your change affects (compared with gitlab/main), like a merge request build
#   scripts/check.sh all             every layer, like a build of main
#   scripts/check.sh 40-eks 45-gitlab-server   exactly these layers
#   scripts/check.sh --plan ...      also run plan with your own AWS credentials (read-only, changes nothing), with each
#                                    layer's own terraform.tfvars (or the folder in TF_VARS_DIR, if you set it)
#
# It runs: format (all layers), then for each layer validate, lint and scan (scan is report-only).
# It does not stop at the first failure: you see every problem in one run, and the exit code is 1 if any check failed.
# Settings are the ones of tf.sh (TF_CACHE, TF_MEMORY...).
source "$(dirname "$0")/lib.sh"

PLAN=0
LAYERS=()
for a in "$@"; do
  case "$a" in
    --plan) PLAN=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) LAYERS+=("$a") ;;
  esac
done

main() {
  local base
  base="$(git -C "$ROOT" rev-parse --verify -q gitlab/main || git -C "$ROOT" rev-parse --verify -q origin/main || true)"

  if [[ ${#LAYERS[@]} -eq 0 ]]; then
    [[ -n "$base" ]] || { warn "No gitlab/main or origin/main to compare with: name the layers, or use 'all'"; exit 2; }
    mapfile -t LAYERS < <(TF_INCLUDE_WORKTREE=1 "$ROOT/scripts/tf-layers.sh" "$base")
  elif [[ "${LAYERS[0]}" == all ]]; then
    mapfile -t LAYERS < <("$ROOT/scripts/tf-layers.sh" all)
  fi
  say "Layers to check: ${LAYERS[*]:-none}"

  # A clean copy, as in CI: init in the working folder leaves links and backend settings that confuse later runs.
  # Under the cache folder, not /tmp (RAM). Without .terraform, state files and the git-ignored tfvars.
  local work failed=() started=$SECONDS
  mkdir -p "${TF_CACHE:-$HOME/.cache/tf-plugin-cache}/.."
  work="$(mktemp -d "$HOME/.cache/tf-check.XXXXXX")"
  trap "rm -rf '$work'" EXIT   # double quotes: $work is local to main() and gone when the trap runs
  (cd "$ROOT" && tar --exclude='.terraform' --exclude='.terragrunt-cache' --exclude='*.tfstate*' --exclude='terraform.tfvars' -cf - terraform .tflint.hcl $( [[ -f .trivyignore ]] && echo .trivyignore )) | tar -C "$work" -xf -
  export TF_ROOT="$work/terraform"

  # The clean copy has no terraform.tfvars (git-ignored, and it holds your IP ranges), so a plan of layers 30 and 40
  # would stop with "No value for required variable". Give the plan each layer's own file from the working folder,
  # as <layer>.tfvars, the same way Jenkins reads /var/lib/jenkins/tf-vars. A TF_VARS_DIR you set yourself wins.
  if (( PLAN )) && [[ -z "${TF_VARS_DIR:-}" ]]; then
    local f
    mkdir -p "$work/tfvars"
    for f in "$ROOT"/terraform/*/terraform.tfvars; do
      [[ -f "$f" ]] && cp "$f" "$work/tfvars/$(basename "$(dirname "$f")").tfvars"
    done
    export TF_VARS_DIR="$work/tfvars"
  fi

  run() { # run LABEL COMMAND...  -> prints the time, remembers a failure, never stops the script
    local label="$1" t=$SECONDS; shift
    if "$@"; then printf '   ok    %-22s %ss\n' "$label" "$((SECONDS - t))"
    else printf '   FAIL  %-22s %ss\n' "$label" "$((SECONDS - t))"; failed+=("$label"); fi
  }

  say "Format (all layers)"
  run "fmt" "$ROOT/scripts/tf.sh" all fmt

  local l
  for l in "${LAYERS[@]}"; do
    say "$l"
    run "$l validate" "$ROOT/scripts/tf.sh" "$l" check
    run "$l lint" "$ROOT/scripts/tf.sh" "$l" lint
    run "$l scan" "$ROOT/scripts/tf.sh" "$l" scan
    if (( PLAN )) && [[ "$l" != 00-bootstrap ]]; then run "$l plan" "$ROOT/scripts/tf.sh" "$l" plan; fi
  done

  say "Done in $((SECONDS - started))s"
  if (( ${#failed[@]} )); then warn "Failed: ${failed[*]}"; exit 1; fi
  echo "All checks passed."
}

main
