#!/usr/bin/env bash
# Forward cluster Services to local names with kubefwd, e.g. http://weatherapp.weatherapp/
# Usage: fwd.sh [namespace ...]   (default: weatherapp redis postgres mongo argocd monitoring)
source "$(dirname "$0")/lib.sh"
require_tools kubectl

command -v kubefwd >/dev/null || { warn "kubefwd not installed"; exit 1; }
cluster_exists || { warn "EKS cluster '$CLUSTER' is not running (run up.sh first)"; exit 1; }

NAMESPACES=("$@")
[[ ${#NAMESPACES[@]} -gt 0 ]] || NAMESPACES=(weatherapp redis postgres mongo argocd monitoring)

# kubefwd needs root; keep HOME and PATH so root sees the EKS kubeconfig
say "Forwarding: ${NAMESPACES[*]} (sudo password may be asked)"
ARGS=()
for ns in "${NAMESPACES[@]}"; do ARGS+=(-n "$ns"); done
exec sudo env "HOME=$HOME" "PATH=$PATH" kubefwd svc "${ARGS[@]}" --context "$(kubectl config current-context)"
