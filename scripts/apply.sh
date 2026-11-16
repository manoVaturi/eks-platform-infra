#!/usr/bin/env bash
# Apply ONE layer (Terragrunt over Terraform) the safe way: plan, show what will happen, ask, then apply EXACTLY that plan.
# Between the plan you read and the apply there is no gap: the apply uses the saved plan file, made seconds ago by you.
#
#   scripts/apply.sh LAYER                      plan, review, apply   (LAYER is a folder of terraform/, e.g. 32-ci-plan)
#   scripts/apply.sh 30-cicd -var edge_enabled=true      anything after the layer goes to the plan (terraform apply of a saved plan takes no variables)
#
# What it protects you from:
#   - the wrong account or the wrong folder: it prints who you are and which layer, before anything
#   - a plain apply in layer 30 or 35 while the shared ALB is off, which recreates the ALB: it refuses (use up.sh)
#   - a surprise destroy or replace: it lists them in red and asks you to type the layer name, not just "yes"
#   - a stale or forged plan: the plan file is made here, applied here, and deleted afterwards (it holds secrets)
# It never runs without a terminal, and it never applies layer 00 (its state is a local file).
#
# EDGE_ALB is the name of the shared ALB it looks for (default weatherapp-jenkins), only for testing the guard.
source "$(dirname "$0")/lib.sh"

EDGE_ALB="${EDGE_ALB:-weatherapp-jenkins}"

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

red() { printf '\033[1;31m%s\033[0m\n' "$*"; }

# The shared ALB exists only while the edge is on (up.sh switches it on, down.sh off)
edge_is_on() { aws elbv2 describe-load-balancers --region "$REGION" --names "$EDGE_ALB" >/dev/null 2>&1; }

main() {
  [[ $# -ge 1 ]] || usage
  [[ "$1" == -h || "$1" == --help ]] && usage
  local layer="${1%/}"; shift
  layer="${layer#terraform/}"
  local extra=("$@")
  local dir="$TF/$layer"

  command -v terragrunt >/dev/null || die "terragrunt is not installed (see .tool-versions)."
  [[ -t 0 ]] || die "No terminal: this script asks you a question, so it will not run from a pipe or a job."
  [[ -d "$dir" ]] || { warn "No layer '$layer'. Layers:"; (cd "$TF" && ls -d [0-9][0-9]-* | sed 's/^/   /'); exit 2; }
  [[ "$layer" != 00-bootstrap ]] || die "00-bootstrap keeps its state in a local file and is never re-applied. See docs/runbook.md, section 2."

  say "Who and where"
  echo "  account:  $(aws sts get-caller-identity --query Account --output text)"
  echo "  identity: $(aws sts get-caller-identity --query Arn --output text)"
  echo "  layer:    $layer"
  [[ ${#extra[@]} -eq 0 ]] || echo "  plan arguments: ${extra[*]}"

  # The trap (docs/runbook.md, section 7): layers 30 and 35 with the edge off and no edge_enabled given
  case "$layer" in
    30-cicd|35-gitlab-data)
      if ! edge_is_on && ! [[ " ${extra[*]} " == *"edge_enabled"* ]]; then
        die "The shared ALB '$EDGE_ALB' does not exist (the edge is off). A plain apply in $layer would RECREATE it. Use ./scripts/up.sh, or pass -var edge_enabled=true or -var edge_enabled=false on purpose."
      fi ;;
    40-eks|45-gitlab-server)
      warn "$layer is normally created by up.sh and destroyed by down.sh. Applying it by hand is fine while the project is up." ;;
  esac

  # The plan file holds secret values: a private folder, removed when we leave
  umask 077
  local work plan
  work="$(mktemp -d "$HOME/.cache/tf-apply.XXXXXX" 2>/dev/null || mktemp -d)"
  trap "rm -rf '$work'" EXIT
  plan="$work/$layer.tfplan"

  cd "$dir" || exit 1
  say "$layer: init"
  terragrunt init --non-interactive --log-disable -input=false >/dev/null

  say "$layer: plan (changes nothing yet)"
  local rc=0
  # --log-disable: Terragrunt prints only Terraform's own text, which the greps below read
  terragrunt plan --non-interactive --log-disable -input=false -lock-timeout=60s -detailed-exitcode -out="$plan" "${extra[@]}" >"$work/plan.log" 2>&1 || rc=$?
  case "$rc" in
    0) cat "$work/plan.log" | tail -6; say "$layer: no changes, nothing to apply."; return 0 ;;
    1) cat "$work/plan.log"; die "terraform plan failed." ;;
  esac

  # The short list, from the plan file itself (what will be applied), not from the log
  terragrunt show --non-interactive --log-disable -no-color "$plan" >"$work/plan.txt"
  local added changed replaced destroyed
  added="$(grep -c ' will be created$' "$work/plan.txt" || true)"
  changed="$(grep -c ' will be updated in-place$' "$work/plan.txt" || true)"
  replaced="$(grep -c ' must be replaced$' "$work/plan.txt" || true)"
  destroyed="$(grep -c ' will be destroyed$' "$work/plan.txt" || true)"

  say "$layer: what will happen"
  grep -E '^  # .* (will be created|will be updated in-place|must be replaced|will be destroyed)$' "$work/plan.txt" \
    | sed 's/^  # //' | while IFS= read -r line; do
        case "$line" in
          *"must be replaced"|*"will be destroyed") red "  $line" ;;
          *) echo "  $line" ;;
        esac
      done
  echo
  echo "  $added to add, $changed to change, $replaced to replace, $destroyed to destroy"

  local answer need="yes"
  if (( replaced + destroyed > 0 )); then
    red "  This plan DESTROYS or REPLACES resources. Read the red lines above."
    need="$layer"
  fi

  while true; do
    echo
    read -r -p "Type '$need' to apply this plan, 'show' to read the full plan, anything else cancels: " answer
    case "$answer" in
      show) ${PAGER:-less} "$work/plan.txt" || cat "$work/plan.txt" ;;
      "$need") break ;;
      *) echo "Cancelled. Nothing was changed."; return 0 ;;
    esac
  done

  say "$layer: apply (exactly the plan above)"
  terragrunt apply --non-interactive -input=false -lock-timeout=60s "$plan"
  say "$layer: applied."
}

main "$@"
