#!/usr/bin/env bash
# Verifies the repository settings this repo's automation depends on:
#   - an active ruleset protects the default branch (no deletion, no force push)
#   - the build + smoke-test job is a required status check, pinned to GitHub Actions
#   - every required check is really produced by a workflow job (a renamed or
#     stale check would block every merge forever)
#   - auto-merge and squash merge are enabled (used by the merge-dependabot job)
#
# Usage: scripts/check-ruleset.sh [owner/repo]
# Needs gh (authenticated) and jq. In CI GH_TOKEN=$GITHUB_TOKEN is enough; run it
# locally as a repo admin to also verify the merge settings and see the bypass list.
set -euo pipefail

REQUIRED_CHECK="${REQUIRED_CHECK:-build-and-push}"
GITHUB_ACTIONS_APP_ID=15368

for tool in gh jq; do
  command -v "$tool" >/dev/null || { echo "FAIL $tool is required"; exit 1; }
done

REPO="${1:-${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}}"
WORKFLOWS="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows"

failures=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
note() { echo "info $1"; }

repo_json="$(gh api "repos/${REPO}")"
default_branch="$(jq -r .default_branch <<<"$repo_json")"
ref="refs/heads/${default_branch}"
echo "Repository: ${REPO} (default branch: ${default_branch})"

# Active branch rulesets that apply to the default branch.
applying='[]'
for id in $(gh api "repos/${REPO}/rulesets" \
  --jq '.[] | select(.target == "branch" and .enforcement == "active") | .id'); do
  rs="$(gh api "repos/${REPO}/rulesets/${id}")"
  if jq -e --arg ref "$ref" '
      .conditions.ref_name as $r
      | (($r.include // []) | any(. == "~DEFAULT_BRANCH" or . == "~ALL" or . == $ref))
        and ((($r.exclude // []) | any(. == "~DEFAULT_BRANCH" or . == $ref)) | not)
    ' <<<"$rs" >/dev/null; then
    applying="$(jq --argjson rs "$rs" '. + [$rs]' <<<"$applying")"
  fi
done

if [[ "$(jq length <<<"$applying")" -eq 0 ]]; then
  fail "no active ruleset applies to ${default_branch}"
else
  pass "active ruleset(s) on ${default_branch}: $(jq -r '[.[].name] | join(", ")' <<<"$applying")"
  rules="$(jq '[.[].rules[]]' <<<"$applying")"

  for type in deletion non_fast_forward; do
    if jq -e --arg t "$type" 'any(.[]; .type == $t)' <<<"$rules" >/dev/null; then
      pass "rule '${type}' is enabled"
    else
      fail "rule '${type}' is missing"
    fi
  done

  if jq -e --arg c "$REQUIRED_CHECK" --argjson app "$GITHUB_ACTIONS_APP_ID" '
      any(.[] | select(.type == "required_status_checks")
            | .parameters.required_status_checks[];
          .context == $c and .integration_id == $app)
    ' <<<"$rules" >/dev/null; then
    pass "required check '${REQUIRED_CHECK}' is pinned to GitHub Actions"
  else
    fail "required check '${REQUIRED_CHECK}' from GitHub Actions (app ${GITHUB_ACTIONS_APP_ID}) is missing"
  fi

  # Every required check must be produced by a workflow job.
  while IFS= read -r ctx; do
    [[ -z "$ctx" ]] && continue
    if grep -qxF "  ${ctx}:" "$WORKFLOWS"/*.yml || grep -qxF "    name: ${ctx}" "$WORKFLOWS"/*.yml; then
      pass "required check '${ctx}' is a job in .github/workflows"
    else
      fail "required check '${ctx}' is not a job in .github/workflows, merges would be blocked forever"
    fi
  done < <(jq -r '.[] | select(.type == "required_status_checks")
                  | .parameters.required_status_checks[].context' <<<"$rules")

  # The bypass list is only returned to repo admins.
  if jq -e 'all(.[]; has("bypass_actors"))' <<<"$applying" >/dev/null; then
    bypass="$(jq -r '[.[].bypass_actors[] | "\(.actor_type)/\(.bypass_mode)"] | join(", ")' <<<"$applying")"
    note "bypass actors: ${bypass:-none}"
  else
    note "bypass list is not visible with this token"
  fi
fi

# Merge settings used by the merge-dependabot job.
for setting in allow_auto_merge allow_squash_merge; do
  value="$(jq -r --arg s "$setting" 'if has($s) and .[$s] != null then .[$s] | tostring else "unknown" end' <<<"$repo_json")"
  case "$value" in
    true) pass "${setting} is enabled" ;;
    false) fail "${setting} is disabled (needed by the merge-dependabot job)" ;;
    *) note "${setting} is not visible with this token, run this script locally as an admin" ;;
  esac
done

if [[ "$failures" -ne 0 ]]; then
  echo "${failures} check(s) failed"
  exit 1
fi
echo "All checks passed"
