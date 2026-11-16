#!/usr/bin/env bash
# Which Terraform layers does a change affect? Prints one layer per line, in apply order.
# Prints nothing for a change that touches no Terraform (docs only), and the caller skips the stages.
#
#   scripts/tf-layers.sh origin/main   layers changed since the merge base with origin/main, plus the layers that read their outputs
#   scripts/tf-layers.sh all           every layer (builds of main use this)
#   scripts/tf-layers.sh --deps        the dependency table, read from the dependency blocks in terragrunt.hcl
#
# Rules:
#   a file inside terraform/NN-name/        the layer NN-name is affected
#   outputs.tf of a layer changed           the layers that read its state are affected too
#   Jenkinsfile, scripts/tf*.sh, lib.sh,    every layer: they change how all layers are checked
#     terraform/*.hcl (root.hcl), terraform/_shared/*, .tflint.hcl, .trivyignore
#   anything else (docs/runbook.md, up.sh)     no layer
#
# TF_REPO points at another repo checkout (used to test this script against a throw-away repo).
# TF_INCLUDE_WORKTREE=1 also counts uncommitted and new files (scripts/check.sh sets it, so you can check before you commit).
source "$(dirname "$0")/lib.sh"

REPO="${TF_REPO:-$ROOT}"
TF_DIR="$REPO/terraform"

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

all_layers() { find "$TF_DIR" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9]-*' -printf '%f\n' | sort; }

# The layers that layer $1 reads, from the dependency blocks in its terragrunt.hcl
# (config_path = "../10-network" -> 10-network).
reads() {
  grep -h -o 'config_path *= *"[^"]*"' "$TF_DIR/$1/terragrunt.hcl" 2>/dev/null | sed 's/.*"\(.*\)"/\1/; s#.*/##' | sort -u || true
}

# The layers that read layer $1.
dependents() {
  local l
  for l in $(all_layers); do
    reads "$l" | grep -qx "$1" && echo "$l"
  done
  return 0
}

print_deps() {
  local l
  printf '%-16s %s\n' LAYER READS
  for l in $(all_layers); do
    printf '%-16s %s\n' "$l" "$(reads "$l" | tr '\n' ' ')"
  done
}

# The files this change touches. CI compares the commits; on your laptop you may also want what is not committed yet.
changed_files() {
  local base="$1"
  if [[ "${TF_INCLUDE_WORKTREE:-0}" == 1 ]]; then
    git -C "$REPO" diff --name-only "$(git -C "$REPO" merge-base "$base" HEAD)" || return 1
    git -C "$REPO" ls-files --others --exclude-standard
  else
    git -C "$REPO" diff --name-only "$base"...HEAD
  fi
}

in_list() { [[ " $2 " == *" $1 "* ]]; }

main() {
  [[ $# -eq 1 ]] || usage
  case "$1" in
    --deps) print_deps; return ;;
    all)    all_layers; return ;;
    -h|--help) usage ;;
  esac

  local base="$1" files
  if ! files="$(changed_files "$base" 2>/dev/null)"; then
    warn "Cannot compare with '$base'; checking every layer to be safe." >&2
    all_layers
    return
  fi

  local everything=0 f layer changed="" outputs_changed=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case "$f" in
      terraform/[0-9][0-9]-*/*)
        layer="${f#terraform/}"; layer="${layer%%/*}"
        in_list "$layer" "$changed" || changed="$changed $layer"
        if [[ "${f##*/}" == outputs.tf ]]; then in_list "$layer" "$outputs_changed" || outputs_changed="$outputs_changed $layer"; fi
        ;;
      Jenkinsfile|.tflint.hcl|.trivyignore|scripts/tf.sh|scripts/tf-layers.sh|scripts/lib.sh|terraform/*.hcl|terraform/_shared/*)
        everything=1 ;;
    esac
  done <<<"$files"

  if (( everything )); then all_layers; return; fi

  local l affected="$changed"
  for l in $outputs_changed; do
    for d in $(dependents "$l"); do
      in_list "$d" "$affected" || affected="$affected $d"
    done
  done

  # Only layers that still exist (a deleted layer has nothing to check), in apply order
  for l in $(all_layers); do
    in_list "$l" "$affected" && echo "$l"
  done
  return 0
}

main "$@"
