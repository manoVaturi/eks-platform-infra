#!/usr/bin/env bash
# Checks that GitLab protects what it should (read-only). Exit code = number of failed checks.
# Needs a read_api token in ~/.weatherapp/gitlab-check-token.
source "$(dirname "$0")/lib.sh"

GITLAB="${GITLAB_URL:-https://gitlab.manovaturi.com}"
TOKEN_FILE="${GITLAB_API_TOKEN_FILE:-$HOME/.weatherapp/gitlab-check-token}"
SOURCE="weatherapp%2Fweatherapp-source"
GITOPS="weatherapp%2Fweatherapp-gitops"
BOT_TOKEN_NAME="jenkins-gitops"

[[ -s "$TOKEN_FILE" ]] || { warn "No token at $TOKEN_FILE (a personal access token with the read_api scope, one line)."; exit 1; }
TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"

# the token goes through stdin so it never shows on a command line
api() { printf 'header = "PRIVATE-TOKEN: %s"\n' "$TOKEN" | curl -fsS --max-time 15 -K - "$GITLAB/api/v4/$1" 2>/dev/null; }

# prints the access levels of a list: 0 = No one, 30 = Developers, 40 = Maintainers
levels() { sed -n -E "s/.*\"$1\":\[([^]]*)\].*/\1/p" <<<"$2" | grep -o '"access_level":[0-9]*' | cut -d: -f2 | sort -un | tr '\n' ' ' | sed 's/ $//' || true; }

FAILS=0
report() {  # report PASS|FAIL "what" "detail"
  if [[ "$1" == PASS ]]; then printf '  \033[1;32mPASS\033[0m  %s\n' "$2"; else printf '  \033[1;31mFAIL\033[0m  %s\n        %s\n' "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

say "Branch protection"
json="$(api "projects/$SOURCE/protected_branches/main" || true)"
if [[ -z "$json" ]]; then
  report FAIL "weatherapp-source: main is protected" "main is not protected, or the token cannot read it. Settings, Repository, Protected branches."
else
  [[ "$(levels push_access_levels "$json")" == "0" ]] \
    && report PASS "weatherapp-source: nobody may push to main (everything goes through a merge request)" \
    || report FAIL "weatherapp-source: nobody may push to main" "Allowed to push and merge is '$(levels push_access_levels "$json")' (0 = No one). Set it to No one."
  [[ "$json" == *'"allow_force_push":false'* ]] \
    && report PASS "weatherapp-source: force push to main is off" || report FAIL "weatherapp-source: force push to main is off" "Turn off Allow force push."
fi
json="$(api "projects/$GITOPS/protected_branches/main" || true)"
if [[ -z "$json" ]]; then
  report FAIL "weatherapp-gitops: main is protected" "main is not protected, or the token cannot read it. Settings, Repository, Protected branches."
else
  [[ "$(levels push_access_levels "$json")" == "40" ]] \
    && report PASS "weatherapp-gitops: only Maintainers may push to main (Jenkins's bot is a Maintainer)" \
    || report FAIL "weatherapp-gitops: only Maintainers may push to main" "Allowed to push and merge is '$(levels push_access_levels "$json")' (40 = Maintainers). With 0, the dev bump is refused; with 30, any Developer may push."
  [[ "$json" == *'"allow_force_push":false'* ]] \
    && report PASS "weatherapp-gitops: force push to main is off" || report FAIL "weatherapp-gitops: force push to main is off" "Turn off Allow force push."
fi

say "Release tags"
json="$(api "projects/$SOURCE/protected_tags/v%2A" || true)"
if [[ -z "$json" ]]; then
  report FAIL "weatherapp-source: the tags v* are protected" "No protected tag v*. Settings, Repository, Protected tags."
else
  [[ "$(levels create_access_levels "$json")" == "40" ]] \
    && report PASS "weatherapp-source: only Maintainers may create v* tags" \
    || report FAIL "weatherapp-source: only Maintainers may create v* tags" "Allowed to create is '$(levels create_access_levels "$json")' (40 = Maintainers)."
fi

say "The Jenkins bot token (weatherapp-gitops)"
json="$(api "projects/$GITOPS/access_tokens" || true)"
tok="$(sed 's/},{/}\n{/g' <<<"$json" | grep "\"name\":\"$BOT_TOKEN_NAME\"" | grep '"active":true' | head -1 || true)"
if [[ -z "$tok" ]]; then
  report FAIL "a project access token '$BOT_TOKEN_NAME' exists and is active" "None found. Settings, Access tokens in weatherapp-gitops (Maintainer, read_repository and write_repository)."
else
  report PASS "a project access token '$BOT_TOKEN_NAME' exists and is active"
  [[ "$tok" == *'"access_level":40'* && "$tok" == *'write_repository'* ]] \
    && report PASS "it is a Maintainer and may write to the repository" || report FAIL "it is a Maintainer with write_repository" "Needs role Maintainer and the scopes read_repository and write_repository."
  expires="$(grep -o '"expires_at":"[0-9-]*"' <<<"$tok" | cut -d'"' -f4 || true)"
  if [[ -z "$expires" ]]; then
    report PASS "it has no expiry date (consider setting one)"
  else
    days=$(( ( $(date -d "$expires" +%s) - $(date +%s) ) / 86400 ))
    if (( days >= 30 )); then report PASS "it expires on $expires ($days days left)"; else report FAIL "it does not expire within 30 days" "It expires on $expires ($days days). Create a new token and update the Jenkins credential gitlab-gitops-bot, or dev deploys stop."; fi
  fi
fi

echo
if (( FAILS == 0 )); then say "All checks passed"; else warn "$FAILS check(s) failed. docs/runbook.md (Protect the repositories) says how to fix each one."; fi
exit "$FAILS"
